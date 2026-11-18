// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/space_overview/space_overview.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

/// Links in messages reach `openMatrixToUrl` without the scan checks: the
/// servers it joins through are limited there too.
void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.api['POST']!['/client/v3/publicRooms'] = (_) => {
      'chunk': <Object?>[],
      'total_room_count_estimate': 0,
    };
  });
  tearDown(harness.tearDown);

  Future<void> open(WidgetTester tester, String link) async {
    await harness.open(tester, path: '/settings');
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(UrlLauncher(context, link).openMatrixToUrl());
    await harness.settle(tester, rounds: 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 4);
  }

  testWidgets('the join prompt names the room and uses the localized title', (
    tester,
  ) async {
    await open(
      tester,
      'https://matrix.to/#/!room:example.org?via=good.example',
    );
    final l10n = L10n.of(tester.element(find.byType(Scaffold).first));
    expect(find.text(l10n.joinRoom), findsWidgets);
    expect(find.textContaining('!room:example.org'), findsWidgets);
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets(
    'a link with hostile via values joins through valid servers only',
    (tester) async {
      final via = [
        'good.example',
        'evil/path',
        'user@evil.example',
        '[::1]',
        for (var n = 0; n < 20; n++) 'extra$n.example',
      ].map((server) => 'via=$server').join('&');
      await open(tester, 'https://matrix.to/#/!room:example.org?$via');
      final l10n = L10n.of(tester.element(find.byType(Scaffold).first));
      await tester.tap(find.text(l10n.ok));
      await harness.settle(tester, rounds: 4);
      final joins = api.requests('/join/', method: 'POST');
      expect(joins, hasLength(1));
      final servers = joins.single.url.queryParametersAll['via']!;
      expect(servers.length, lessThanOrEqualTo(5));
      expect(servers.first, 'good.example');
      expect(
        servers.every(
          (s) => !s.contains('/') && !s.contains('@') && !s.contains('['),
        ),
        isTrue,
      );
      await harness.finish(tester);
    },
  );

  testWidgets('a link to a joined space opens its overview', (tester) async {
    final space =
        Room(
          id: '!space:example.org',
          client: harness.client,
          membership: Membership.join,
        )..setState(
          Event(
            type: EventTypes.RoomCreate,
            stateKey: '',
            content: {'type': RoomCreationTypes.mSpace},
            room: Room(id: '!space:example.org', client: harness.client),
            eventId: r'$create',
            senderId: '@admin:example.org',
            originServerTs: DateTime(2030),
          ),
        );
    harness.client.rooms.add(space);
    await open(tester, 'https://matrix.to/#/!space:example.org');
    expect(find.byType(SpaceOverview), findsOneWidget);
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });
}
