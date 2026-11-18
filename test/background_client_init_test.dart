// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/safe_init_client.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/client_init_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'utils/recording_api.dart';
import 'utils/set_up_vodozemac.dart';

class _SpyClient extends SafeInitClient {
  _SpyClient(super.clientName, {required super.database, super.httpClient});

  int disposals = 0;

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposals++;
    await super.dispose(closeDatabase: closeDatabase);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Database sqlite;
  late Client client;
  final secretDeletes = <String>[];

  setUp(() async {
    await setUpVodozemac();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    secretDeletes.clear();
    dir = Directory.systemTemp.createTempSync('background_init_test');
    sqlite = await databaseFactoryFfi.openDatabase(
      '${dir.path}/bg.sqlite',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    client = await ClientManager.createClient(
      'bg',
      AppSettings.store,
      background: true,
      httpClient: RecordingApi(),
      database: await MatrixSdkDatabase.init(
        'bg',
        database: sqlite,
        sqfliteFactory: databaseFactoryFfi,
        secureStorage: (
          read: (key) async => null,
          write: (key, value) async {},
          delete: (key) async => secretDeletes.add(key),
        ),
      ),
    );
  });

  tearDown(() async {
    await client.dispose(closeDatabase: false);
    if (sqlite.isOpen) await sqlite.close();
    dir.deleteSync(recursive: true);
  });

  test('a storage error in a background init keeps the database and the '
      'session, and is raised once', () async {
    expect(client, isA<SafeInitClient>());
    final file = File('${dir.path}/bg.sqlite');
    final length = file.lengthSync();
    await sqlite.close();

    var failures = 0;
    try {
      await initBackgroundClient(client);
    } on ClientInitException catch (e) {
      failures++;
      expect(keepsDataAfterInitFailure(e), isTrue);
    }

    expect(failures, 1);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), length);
    expect(secretDeletes, isEmpty);
  });

  group('runBackgroundClientTask covers the whole path (F6)', () {
    late ReceivePort port;
    late List<Object?> messages;

    bool slotTaken() =>
        IsolateNameServer.lookupPortByName(AppConfig.pushIsolatePortName) !=
        null;

    setUp(() {
      port = ReceivePort();
      messages = [];
      port.listen(messages.add);
      IsolateNameServer.removePortNameMapping(AppConfig.pushIsolatePortName);
    });

    tearDown(() {
      IsolateNameServer.removePortNameMapping(AppConfig.pushIsolatePortName);
      port.close();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('the port is registered while the task runs and removed after, with '
        'DONE sent', () async {
      var during = false;
      await expectLater(
        runBackgroundClientTask(port, () async {
          during = slotTaken();
          throw StateError('x');
        }, (_) async {}),
        throwsA(isA<StateError>()),
      );
      await settle();

      expect(during, isTrue);
      expect(slotTaken(), isFalse);
      expect(messages, ['DONE']);
    });

    test('a client that cannot be created cleans up too', () async {
      await expectLater(
        runBackgroundClientTask(
          port,
          () async => throw const DatabaseOpenFailedException('bg', 'x'),
          (_) async {},
        ),
        throwsA(isA<DatabaseOpenFailedException>()),
      );
      await settle();

      expect(slotTaken(), isFalse);
      expect(messages, ['DONE']);
    });

    test('a storage error in init keeps the data, disposes the client and '
        'cleans up', () async {
      final file = File('${dir.path}/bg.sqlite');
      final length = file.lengthSync();
      final spy = _SpyClient(
        'bg',
        database: await MatrixSdkDatabase.init(
          'bg',
          database: sqlite,
          sqfliteFactory: databaseFactoryFfi,
          secureStorage: (
            read: (key) async => null,
            write: (key, value) async {},
            delete: (key) async => secretDeletes.add(key),
          ),
        ),
        httpClient: RecordingApi(),
      );
      await sqlite.close();
      var used = false;

      await expectLater(
        runBackgroundClientTask(port, () async => spy, (_) async {
          used = true;
        }),
        throwsA(isA<ClientInitException>()),
      );
      await settle();

      expect(used, isFalse);
      expect(spy.disposals, 1);
      expect(file.lengthSync(), length);
      expect(secretDeletes, isEmpty);
      expect(slotTaken(), isFalse);
      expect(messages, ['DONE']);
    });

    test('a client that is not signed in is an error and cleans up', () async {
      await expectLater(
        runBackgroundClientTask(port, () async => client, (_) async {}),
        throwsA(isA<Exception>()),
      );
      await settle();

      expect(slotTaken(), isFalse);
      expect(messages, ['DONE']);
    });
  });

  test('the notification tap runs through runBackgroundClientTask (F6)', () {
    expect(
      File('lib/utils/notification_background_handler.dart').readAsStringSync(),
      contains('await runBackgroundClientTask('),
    );
  });
}
