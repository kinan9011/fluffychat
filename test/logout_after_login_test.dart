// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'utils/test_client.dart';

const _userId = '@r1:fakeServer.notExisting';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final deleted = <String>[];
  late Client client;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            if (call.method == 'delete') {
              deleted.add((call.arguments as Map)['key'] as String);
            }
            return null;
          },
        );
    final warm = await prepareTestClient(clientName: 'LoginWarm');
    await warm.dispose(closeDatabase: true);
    client = Client(
      'LoginBare',
      httpClient: FakeMatrixApi(),
      database: await MatrixSdkDatabase.init(
        'loginbare',
        database: await databaseFactoryFfi.openDatabase(
          ':memory:',
          options: OpenDatabaseOptions(singleInstance: false),
        ),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    client.backgroundSync = false;
  });

  testWidgets(
    'signing in and out in one session still clears the status timer of that '
    'account and keeps the remembered recovery key',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        FluffyChatApp(
          clients: [client],
          store: prefs,
          appLockSettings: (pincode: null, useBiometrics: false),
        ),
      );
      FluffyChatApp.router.go('/home');
      await tester.pump(const Duration(milliseconds: 500));
      expect(client.userID, isNull, reason: 'the app started signed out');
      await tester.runAsync(
        () => client.init(
          waitForFirstSync: false,
          newHomeserver: Uri.parse('https://fakeServer.notExisting'),
          newDeviceID: 'LOGINDEV',
          newDeviceName: 'Login Tester',
          newToken: 'login-token',
          newUserID: _userId,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.userID, _userId);
      await StatusClearStore().arm(
        _userId,
        'status text',
        DateTime.now().add(const Duration(hours: 1)),
      );
      await tester.runAsync(client.logout);
      for (var i = 0; i < 60; i++) {
        if (StatusClearStore().read().isEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(StatusClearStore().read(), isEmpty);
      expect(deleted, isNot(contains('ssss_recovery_key_$_userId')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 35));
    },
  );
}
