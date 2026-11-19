// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/client_init_exception.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/client_manager.dart';
import 'package:odango/utils/init_with_restore.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'package:odango/utils/matrix_sdk_extensions/safe_init_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/sqflite_ffi_exception.dart';

import 'utils/recording_api.dart';
import 'utils/set_up_vodozemac.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

DatabaseException _dbError(int code) =>
    SqfliteFfiException(code: 'sqlite_error', message: 'x', resultCode: code);

class _FakeNotifications extends FlutterLocalNotificationsPlatform {}

class _ThrowingGetClientDatabase implements DatabaseApi {
  _ThrowingGetClientDatabase(this.error);

  final Object error;
  int clears = 0;

  @override
  Future<Map<String, dynamic>?> getClient(String name) => throw error;

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> delete() async {}

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File dbFile;
  late Database sqlite;
  late MatrixSdkDatabase database;
  final secretDeletes = <String>[];
  late RecordingApi api;
  Client? client;

  setUp(() async {
    await setUpVodozemac();
    api = RecordingApi();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
    secretDeletes.clear();
    FlutterLocalNotificationsPlatform.instance = _FakeNotifications();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
    dir = Directory.systemTemp.createTempSync('safe_init_client_test');
    dbFile = File('${dir.path}/safe.sqlite');
    sqlite = await databaseFactoryFfi.openDatabase(
      dbFile.path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    database = await MatrixSdkDatabase.init(
      'safe',
      database: sqlite,
      sqfliteFactory: databaseFactoryFfi,
      secureStorage: (
        read: (key) async => null,
        write: (key, value) async {},
        delete: (key) async => secretDeletes.add(key),
      ),
    );
  });

  tearDown(() async {
    await client?.dispose(closeDatabase: false);
    client = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    if (sqlite.isOpen) await sqlite.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<Client> create(DatabaseApi db) async =>
      client = await ClientManager.createClient(
        'safe',
        AppSettings.store,
        httpClient: api,
        database: db,
      );

  group('keepsDataAfterInitFailure', () {
    test('storage, file system and network errors keep the data', () {
      final kept = <Object>[
        _dbError(13),
        const FileSystemException('x'),
        const SocketException('x'),
        TimeoutException('x'),
        http.ClientException('x'),
        ClientInitException(const SocketException('x')),
        ClientInitException(_dbError(5)),
        PlatformException(code: 'keystore'),
        ClientInitException(PlatformException(code: 'keystore')),
      ];
      for (final error in kept) {
        expect(
          keepsDataAfterInitFailure(error),
          isTrue,
          reason: error.runtimeType.toString(),
        );
      }
    });

    test('errors about the session itself do not keep it', () {
      final notKept = <Object>[
        const FormatException('x'),
        Exception('olm'),
        StateError('x'),
        ClientInitException(const FormatException('x')),
        ClientInitException(StateError('x')),
      ];
      for (final error in notKept) {
        expect(
          keepsDataAfterInitFailure(error),
          isFalse,
          reason: error.runtimeType.toString(),
        );
      }
    });
  });

  group('SafeInitClient', () {
    test('createClient builds a SafeInitClient', () async {
      expect(await create(database), isA<SafeInitClient>());
    });

    test('a storage error in init keeps the database file and the secrets '
        '(A1)', () async {
      final length = dbFile.lengthSync();
      await sqlite.close();
      final safe = await create(database);

      await expectLater(
        safe.initWithRestore(),
        throwsA(isA<DatabaseOpenFailedException>()),
      );

      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), length);
      expect(secretDeletes, isEmpty);
    });

    test('the SDK on its own does delete the database after the same '
        'failure (A2: proves the setup reaches the SDK clear)', () async {
      await sqlite.close();
      final plain = client = Client(
        'plain',
        httpClient: api,
        database: database,
      );

      await expectLater(plain.init(), throwsA(isA<ClientInitException>()));

      expect(secretDeletes, isNotEmpty);
    });

    test('an error about the session itself still clears once (A4)', () async {
      final failing = _ThrowingGetClientDatabase(const FormatException('x'));
      final safe = await create(failing);
      final reasons = <SessionClearReason>[];
      safe.onSessionCleared.stream.listen(reasons.add);

      await safe.initWithRestore().then<void>(
        (_) {},
        onError: (Object e, StackTrace s) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(failing.clears, 1);
      expect(reasons, [SessionClearReason.initFailed]);
    });

    test('a storage error never reaches the SDK clear', () async {
      final failing = _ThrowingGetClientDatabase(_dbError(5));
      final safe = await create(failing);

      await expectLater(
        safe.initWithRestore(),
        throwsA(isA<DatabaseOpenFailedException>()),
      );

      expect(failing.clears, 0);
    });

    test('a kept failure leaves nothing pending, a stale flag cannot wipe '
        'later (F3)', () async {
      final failing = _ThrowingGetClientDatabase(_dbError(5));
      final safe = await create(failing) as SafeInitClient;
      await safe.clear(reason: SessionClearReason.initFailed);
      await expectLater(
        safe.settleInitFailure(_dbError(5)),
        throwsA(isA<DatabaseOpenFailedException>()),
      );

      await safe.settleInitFailure(const FormatException('x'));

      expect(failing.clears, 0);
    });

    test('a genuine clear after a kept failure still runs (F3)', () async {
      final failing = _ThrowingGetClientDatabase(_dbError(5));
      final safe = await create(failing) as SafeInitClient;
      await safe.clear(reason: SessionClearReason.initFailed);
      await expectLater(
        safe.settleInitFailure(_dbError(5)),
        throwsA(isA<DatabaseOpenFailedException>()),
      );
      await safe.clear(reason: SessionClearReason.initFailed);

      await safe.settleInitFailure(const FormatException('x'));

      expect(failing.clears, 1);
    });

    test('a logout still clears at once (A5)', () async {
      final failing = _ThrowingGetClientDatabase(const FormatException('x'));
      final safe = await create(failing);

      await safe.clear(reason: SessionClearReason.logout);

      expect(failing.clears, 1);
    });
  });
}
