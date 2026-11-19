// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/settings_data/search_index_group.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';
import 'package:odango/widgets/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

const _secret = 'SENTINEL-SECRET-BODY';

IndexedMessage _msg() => IndexedMessage(
  roomId: '!a:example.org',
  eventId: r'$e1:example.org',
  senderId: '@alice:example.org',
  timestamp: 1700000000000,
  kind: SearchKind.text,
  text: _secret,
);

Future<String> _stored(Client client) async => jsonEncode(
  (await client.database.getCustomCacheObject(
    MessageIndex.documentKey,
  ))?.content,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client first;
  late Client second;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    first = await prepareTestClient();
    first.backgroundSync = false;
    second = await prepareTestClient(clientName: 'Second');
    second.backgroundSync = false;
  });

  tearDown(() {
    MatrixState.accountHooks = MatrixState.defaultAccountHooks;
    MessageIndex.forget(first);
    MessageIndex.forget(second);
  });

  testWidgets('clearing empties the index of every logged in account', (
    tester,
  ) async {
    MatrixState.accountHooks = (_, _, _) async {};
    final indexes = [MessageIndex.of(first), MessageIndex.of(second)];
    await tester.runAsync(() async {
      for (final index in indexes) {
        await index.ready;
        index.add(_msg());
      }
    });
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [first, second],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    FluffyChatApp.router.go('/settings/data');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(SearchIndexGroup.rowKey), findsOneWidget);
    final l10n = L10n.of(tester.element(find.byType(SearchIndexGroup)));
    expect(find.text(l10n.searchIndexCount(2)), findsOneWidget);
    await tester.tap(find.byKey(SearchIndexGroup.rowKey));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(l10n.searchIndexClear).last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(indexes[0].length, 0);
    expect(indexes[1].length, 0);
    await tester.runAsync(() async {
      expect(await _stored(first), isNot(contains(_secret)));
      expect(await _stored(second), isNot(contains(_secret)));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 35));
  });
}
