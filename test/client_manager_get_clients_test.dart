// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/src/sqflite_ffi_exception.dart';

import 'utils/set_up_vodozemac.dart';

class _FakeNotifications extends FlutterLocalNotificationsPlatform {}

class _Database implements DatabaseApi {
  _Database(this.getClientError);

  final Object? getClientError;
  int closes = 0;

  @override
  Future<Map<String, dynamic>?> getClient(String name) async {
    final error = getClientError;
    if (error != null) throw error;
    return null;
  }

  @override
  Future<void> clear() async {}

  @override
  Future<void> delete() async {}

  @override
  Future<void> close() async => closes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storageError = SqfliteFfiException(
    code: 'sqlite_error',
    message: 'x',
    resultCode: 5,
  );
  late Map<String, _Database> databases;

  setUp(() async {
    await setUpVodozemac();
    FlutterLocalNotificationsPlatform.instance = _FakeNotifications();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.setStringList(ClientManager.clientNamespace, [
      'a',
      'b',
    ]);
    databases = {};
  });

  Future<List<Client>> load(Map<String, Object?> errors) {
    return ClientManager.getClients(
      store: AppSettings.store,
      create: (name) => ClientManager.createClient(
        name,
        AppSettings.store,
        database: databases[name] = _Database(errors[name]),
      ),
    );
  }

  test('a client whose storage fails stops the start-up (C1)', () async {
    await expectLater(
      load({'a': storageError}),
      throwsA(isA<DatabaseOpenFailedException>()),
    );
  });

  test('the clients that did open are closed first (C2)', () async {
    await expectLater(
      load({'a': storageError}),
      throwsA(isA<DatabaseOpenFailedException>()),
    );

    expect(databases['b']!.closes, greaterThan(0));
  });

  test('another init error is still only logged (C3)', () async {
    await AppSettings.store.setStringList(ClientManager.clientNamespace, ['a']);

    final clients = await load({'a': const FormatException('x')});

    expect(clients, hasLength(1));
  });

  group('persisted call support of a client that is not logged in', () {
    const prefix = ServerCapabilitiesService.callSupportKeyPrefix;

    Future<void> seed(List<String> names) async {
      for (final name in names) {
        await AppSettings.store.setString('$prefix$name', 'supported');
      }
      await AppSettings.store.setString('${prefix}c', 'supported');
    }

    test('is dropped at start with several accounts', () async {
      await seed(['a', 'b']);

      await load({});

      expect(AppSettings.store.getString('${prefix}a'), isNull);
      expect(AppSettings.store.getString('${prefix}b'), isNull);
      expect(
        AppSettings.store.getString('${prefix}c'),
        'supported',
        reason: 'only the clients of this start are touched',
      );
    });

    test('is dropped at start with a single account', () async {
      await AppSettings.store.setStringList(ClientManager.clientNamespace, [
        'a',
      ]);
      await seed(['a']);

      final clients = await load({});

      expect(clients, hasLength(1));
      expect(AppSettings.store.getString('${prefix}a'), isNull);
    });

    test(
      'is kept when the clients are not initialized (push isolate)',
      () async {
        await seed(['a']);

        await ClientManager.getClients(
          initialize: false,
          store: AppSettings.store,
          create: (name) => ClientManager.createClient(
            name,
            AppSettings.store,
            database: _Database(null),
          ),
        );

        expect(AppSettings.store.getString('${prefix}a'), 'supported');
      },
    );
  });
}
