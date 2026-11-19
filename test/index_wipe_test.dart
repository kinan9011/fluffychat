// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';
import 'package:odango/widgets/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

const _secret = 'SENTINEL-SECRET-BODY';

IndexedMessage _msg(String text) => IndexedMessage(
  roomId: '!a:example.org',
  eventId: r'$e1:example.org',
  senderId: '@alice:example.org',
  timestamp: 1700000000000,
  kind: SearchKind.text,
  text: text,
);

Future<String> _stored(Client client) async => jsonEncode(
  (await client.database.getCustomCacheObject(
    MessageIndex.documentKey,
  ))?.content,
);

Future<MessageIndex> _filled(Client client) async {
  final index = MessageIndex.of(client);
  await index.ready;
  index.add(_msg(_secret));
  await index.flush();
  expect(await _stored(client), contains(_secret), reason: 'baseline');
  return index;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client first;
  late Client second;
  late Client third;

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
    third = await prepareTestClient(clientName: 'Third');
  });

  tearDown(() {
    MatrixState.startupHooks = MatrixState.defaultStartupHooks;
    MatrixState.accountHooks = MatrixState.defaultAccountHooks;
    MessageIndex.forget(first);
    MessageIndex.forget(second);
  });

  testWidgets(
    'logging an account out wipes its index and leaves the other one alone',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      MatrixState.accountHooks = (_, _, _) async {};
      await tester.runAsync(() async {
        await _filled(first);
        await _filled(second);
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        FluffyChatApp(
          clients: [first, second],
          store: prefs,
          appLockSettings: (pincode: null, useBiometrics: false),
        ),
      );
      FluffyChatApp.router.go('/rooms');
      await tester.pump(const Duration(milliseconds: 500));
      second.onLoginStateChanged.add(LoginState.loggedOut);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        expect(await _stored(second), isNot(contains(_secret)));
        expect(await _stored(first), contains(_secret));
        expect(MessageIndex.of(first).length, 1);
        expect(MessageIndex.of(second).length, 0);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 35));
    },
  );

  test(
    'clearing the cache wipes the index in memory and in the database',
    () async {
      final index = await _filled(first);
      await first.clearCache();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(index.length, 0);
      expect(await _stored(first), isNot(contains(_secret)));
    },
  );

  test(
    'the SDK logout empties the database; the index forgets with it',
    () async {
      final index = await _filled(third);
      await third.logout();
      await index.wipe();
      expect(index.length, 0);
      expect(await _stored(third), isNot(contains(_secret)));
    },
  );

  test(
    'the index of one account never reads the document of another',
    () async {
      final a = await _filled(first);
      final b = MessageIndex.of(second);
      await b.ready;
      expect(a.length, 1);
      expect(b.length, 0);
      expect(await _stored(second), isNot(contains(_secret)));
    },
  );
}
