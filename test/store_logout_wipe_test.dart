// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/logout_cleanup.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

const _draftSecret = 'SENTINEL-DRAFT-AFTER-LOGOUT';
const _scheduledSecret = 'SENTINEL-SCHEDULED-AFTER-LOGOUT';
const _roomId = '!s3:example.org';

Future<String> _stored(Client client, String key) async =>
    jsonEncode((await client.database.getCustomCacheObject(key))?.content);

ScheduledEntry _entry(String body) => ScheduledEntry(
  id: 'S3ENTRY-0001',
  roomId: _roomId,
  mode: ScheduledMode.device,
  sendAt: DateTime.now().add(const Duration(hours: 1)),
  createdAt: DateTime.now(),
  state: ScheduledState.pending,
  encrypted: false,
  content: {'msgtype': 'm.text', 'body': body},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  final deletedSecrets = <String>[];
  var cancelAllCalls = 0;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            if (call.method == 'delete') {
              deletedSecrets.add((call.arguments as Map)['key'] as String);
            }
            return null;
          },
        );
    client = await prepareTestClient(clientName: 'StoreWipe');
    LogoutCleanup.cancelAllNotifications = () async => cancelAllCalls++;
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
    'drafts and scheduled text written after the real logout never reach the '
    'database again',
    (tester) async {
      await tester.runAsync(() async {
        await DraftStore.of(client).write(_roomId, _draftSecret);
        await ScheduledStore.of(client).put(_entry(_scheduledSecret));
        expect(
          await _stored(client, DraftStore.documentKey),
          contains(_draftSecret),
          reason: 'sanity: the stores do persist while logged in',
        );
        expect(
          await _stored(client, ScheduledStore.documentKey),
          contains(_scheduledSecret),
        );
      });
      final prefs = await SharedPreferences.getInstance();
      final userId = client.userID!;
      await StatusClearStore().arm(
        userId,
        'status text',
        DateTime.now().add(const Duration(hours: 1)),
      );
      await tester.pumpWidget(
        FluffyChatApp(
          clients: [client],
          store: prefs,
          appLockSettings: (pincode: null, useBiometrics: false),
        ),
      );
      FluffyChatApp.router.go('/rooms');
      await tester.pump(const Duration(milliseconds: 500));
      await prefs.setString('draft_!legacy:example.org', 'legacy plaintext');
      await tester.runAsync(client.logout);
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 60; i++) {
        if (cancelAllCalls > 0 &&
            StatusClearStore().read().isEmpty &&
            prefs.getKeys().every((k) => !k.startsWith('draft_'))) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          await _stored(client, DraftStore.documentKey),
          isNot(contains(_draftSecret)),
        );
        expect(
          await _stored(client, ScheduledStore.documentKey),
          isNot(contains(_scheduledSecret)),
        );
        expect(
          deletedSecrets,
          isNot(contains('ssss_recovery_key_$userId')),
          reason: 'the key the user chose to remember stays, as upstream does',
        );
        expect(
          cancelAllCalls,
          1,
          reason: 'the last account that leaves clears the shown notifications',
        );
        expect(prefs.getKeys().where((k) => k.startsWith('draft_')), isEmpty);
        expect(StatusClearStore().read(), isEmpty);
        expect(
          AppSettings.store.getString(StatusClearStore.key),
          isNot(contains(userId)),
        );
        await DraftStore.of(client).write(_roomId, _draftSecret);
        await DraftStore.of(client).flush();
        await expectLater(
          ScheduledStore.of(client).put(_entry(_scheduledSecret)),
          throwsA(isA<ScheduledStorageUnavailable>()),
        );
        expect(
          await _stored(client, DraftStore.documentKey),
          isNot(contains(_draftSecret)),
          reason: 'a late draft write after logout is dropped',
        );
        expect(
          await _stored(client, ScheduledStore.documentKey),
          isNot(contains(_scheduledSecret)),
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 35));
    },
  );
}
