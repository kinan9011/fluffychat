// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/new_private_chat/scan_confirm_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    harness.resetRooms();
    api.clear();
    api.onRequest = null;
    api.api['POST']!['/client/v3/publicRooms'] = (_) => {
      'chunk': <Object?>[],
      'total_room_count_estimate': 0,
    };
  });
  tearDown(harness.tearDown);

  NewPrivateChatController controller(WidgetTester tester) =>
      tester.state<NewPrivateChatController>(find.byType(NewPrivateChat));

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(NewPrivateChat)));

  Future<void> open(WidgetTester tester) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    api.clear();
  }

  const hostile = [
    'javascript:alert(1)',
    'data:text/html;base64,PHNjcmlwdD4=',
    'intent://scan/#Intent;scheme=zxing;end',
    'file:///etc/passwd',
    'https://evil.example/#/@alice:example.org',
    'https://matrix.to.evil.example/#/@alice:example.org',
    'https://matrix.to@evil.example/#/@alice:example.org',
    'http://matrix.to/#/@alice:example.org',
    'https://matrix.tо/#/@alice:example.org',
    'https://matrix.to/#/@ali\\u202Ece:example.org',
    'https://matrix.to/#/@alice:example.org\\nhttps://evil.example',
    'https://matrix.to/#/@alice:evil.example/path',
    'tel:+4912345',
    'mailto:a@example.org',
    'not a link at all',
    '',
  ];

  for (final raw in hostile) {
    testWidgets('a hostile code is refused: ${raw.replaceAll('\n', ' ')}', (
      tester,
    ) async {
      await open(tester);
      unawaited(controller(tester).handleScan(raw));
      await harness.settle(tester, rounds: 3);
      expect(find.text(l10n(tester).qrNotMatrixLink), findsOneWidget);
      expect(find.byType(ScanConfirmSheet), findsNothing);
      expect(api.log, isEmpty, reason: 'nothing may leave the device');
      await harness.finish(tester);
    });
  }

  testWidgets('a valid user link asks first and opens nothing before Open', (
    tester,
  ) async {
    await open(tester);
    unawaited(
      controller(tester).handleScan('https://matrix.to/#/@dave:example.org'),
    );
    await harness.settle(tester, rounds: 3);
    expect(find.byType(ScanConfirmSheet), findsOneWidget);
    expect(find.text('@dave:example.org'), findsOneWidget);
    expect(api.log, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('Cancel opens nothing', (tester) async {
    await open(tester);
    unawaited(
      controller(tester).handleScan('https://matrix.to/#/@dave:example.org'),
    );
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.byKey(ScanConfirmSheet.cancelKey));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(ScanConfirmSheet), findsNothing);
    expect(api.log, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('Open hands a user link to the profile flow', (tester) async {
    await open(tester);
    unawaited(
      controller(tester).handleScan('https://matrix.to/#/@dave:example.org'),
    );
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.byKey(ScanConfirmSheet.openKey));
    await harness.settle(tester, rounds: 4);
    expect(api.requests('/profile/', method: 'GET'), isNotEmpty);
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    expect(api.requests('/createRoom', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a room link joins nothing before the join step is confirmed', (
    tester,
  ) async {
    await open(tester);
    unawaited(
      controller(tester).handleScan(
        'https://matrix.to/#/!room:example.org?via=good.example&via=evil.example/path&via=user@evil.example',
      ),
    );
    await harness.settle(tester, rounds: 3);
    expect(find.text('!room:example.org'), findsOneWidget);
    expect(find.text('good.example'), findsOneWidget);
    expect(find.textContaining('evil'), findsNothing);
    await tester.tap(find.byKey(ScanConfirmSheet.openKey));
    await harness.settle(tester, rounds: 4);
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the join after a scan goes through at most five valid servers', (
    tester,
  ) async {
    await open(tester);
    final via = [
      'good.example',
      'evil/path',
      'user@evil.example',
      for (var n = 0; n < 20; n++) 'extra$n.example',
    ].map((server) => 'via=$server').join('&');
    unawaited(
      controller(
        tester,
      ).handleScan('https://matrix.to/#/!room:example.org?$via'),
    );
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.byKey(ScanConfirmSheet.openKey));
    await harness.settle(tester, rounds: 4);
    // The chat is not known yet: its public directory entry opens first.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 4);
    expect(find.text(l10n(tester).joinRoom), findsWidgets);
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    await tester.tap(find.text(l10n(tester).ok));
    await harness.settle(tester, rounds: 4);
    final joins = api.requests('/join/', method: 'POST');
    expect(joins, hasLength(1));
    final servers = joins.single.url.queryParametersAll['via']!;
    expect(servers.length, lessThanOrEqualTo(5));
    expect(servers.first, 'good.example');
    expect(servers.every((s) => !s.contains('/') && !s.contains('@')), isTrue);
    await harness.finish(tester);
  });

  testWidgets('an alias lookup that names no servers does not crash', (
    tester,
  ) async {
    api.getOverrides['/directory/room/%23alias%3Aexample.org'] = {
      'room_id': '!resolved:example.org',
    };
    await open(tester);
    unawaited(
      controller(tester).handleScan('https://matrix.to/#/#alias:example.org'),
    );
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.byKey(ScanConfirmSheet.openKey));
    await harness.settle(tester, rounds: 4);
    expect(tester.takeException(), isNull);
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the sheet shows what will be opened, not the scanned text', (
    tester,
  ) async {
    await open(tester);
    unawaited(
      controller(
        tester,
      ).handleScan('HTTPS://Matrix.To/#/%40dave%3Aexample.org?evil=1'),
    );
    await harness.settle(tester, rounds: 3);
    expect(find.text('@dave:example.org'), findsOneWidget);
    expect(find.textContaining('evil'), findsNothing);
    await harness.finish(tester);
  });
}
