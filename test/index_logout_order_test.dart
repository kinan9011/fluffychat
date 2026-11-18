// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/message_index.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

const _secret = 'SENTINEL-LOGOUT-ORDER-BODY';

Future<String> _stored(Client client) async => jsonEncode(
  (await client.database.getCustomCacheObject(
    MessageIndex.documentKey,
  ))?.content,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = RecordingApi();
  late Client client;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    client = await prepareTestClient(
      clientName: 'LogoutOrder',
      httpClient: api,
    );
    client.backgroundSync = false;
  });
  // After a real logout `Client.dispose` can wait forever on a busy machine
  // (SDK behaviour, reproduced with only the SDK calls): the assertions are
  // done by now, so cleaning up must not hold the whole run.
  tearDownAll(
    () => client
        .dispose(closeDatabase: true)
        .timeout(const Duration(seconds: 20), onTimeout: () {}),
  );

  testWidgets(
    'the real logout, with a dirty index and its write still pending, leaves '
    'no plaintext, also after the write delay',
    (tester) async {
      late MessageIndex index;
      await tester.runAsync(() async {
        index = MessageIndex.of(client);
        await index.ready;
        index.add(
          IndexedMessage(
            roomId: '!a:example.org',
            eventId: r'$e1:example.org',
            senderId: '@alice:example.org',
            timestamp: 1700000000000,
            kind: SearchKind.text,
            text: _secret,
          ),
        );
      });
      expect(index.length, 1);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        FluffyChatApp(
          clients: [client],
          store: prefs,
          appLockSettings: (pincode: null, useBiometrics: false),
        ),
      );
      FluffyChatApp.router.go('/rooms');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(client.logout);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(api.requests('/logout', method: 'POST'), hasLength(1));
        expect(index.length, 0);
        expect(await _stored(client), isNot(contains(_secret)));
        await Future<void>.delayed(
          MessageIndex.defaultPersistDelay + const Duration(seconds: 1),
        );
        expect(await _stored(client), isNot(contains(_secret)));
        expect(index.length, 0);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 35));
    },
  );
}
