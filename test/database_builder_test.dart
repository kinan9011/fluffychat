// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart' show cacheTypes;
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_file_state.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/src/sqflite_ffi_exception.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _FakeDatabase implements MatrixSdkDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  group('flutterMatrixSdkDatabaseBuilder', () {
    test('a key error is rethrown and never touches the database', () async {
      var constructed = 0;
      final quarantined = <String>[];

      await expectLater(
        flutterMatrixSdkDatabaseBuilder(
          'a',
          construct: (name) async {
            constructed++;
            throw DatabaseKeyUnavailableException(name, 'x');
          },
          quarantine: (name) async => quarantined.add(name),
        ),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );

      expect(constructed, 1);
      expect(quarantined, isEmpty);
    });

    SqfliteFfiException sqliteError(int code) => SqfliteFfiException(
      code: 'sqlite_error',
      message: 'x',
      resultCode: code,
    );

    test(
      'a corrupt database is quarantined, noticed and retried once',
      () async {
        var constructed = 0;
        final quarantined = <String>[];
        final noticed = <String>[];

        await expectLater(
          flutterMatrixSdkDatabaseBuilder(
            'a',
            construct: (name) async {
              constructed++;
              throw sqliteError(11);
            },
            quarantine: (name) async => quarantined.add(name),
            markQuarantined: (name) async => noticed.add(name),
          ),
          throwsA(isA<DatabaseOpenFailedException>()),
        );

        expect(constructed, 2);
        expect(quarantined, ['a']);
        expect(noticed, ['a']);
      },
    );

    test('a corrupt database that opens after the retry is returned', () async {
      var constructed = 0;
      final result = await flutterMatrixSdkDatabaseBuilder(
        'a',
        construct: (name) async {
          if (constructed++ == 0) throw sqliteError(267);
          return _FakeDatabase();
        },
        quarantine: (name) async {},
        markQuarantined: (name) async {},
      );

      expect(result, isA<_FakeDatabase>());
      expect(constructed, 2);
    });

    for (final entry in {
      'SQLITE_BUSY': sqliteError(5),
      'SQLITE_LOCKED': sqliteError(6),
      'SQLITE_FULL': sqliteError(13),
      'SQLITE_IOERR_READ': sqliteError(266),
      'SQLITE_CANTOPEN': sqliteError(14),
      'SQLITE_NOTADB (wrong key looks the same)': sqliteError(26),
      'unclassified': StateError('x'),
    }.entries) {
      test('${entry.key} leaves the file alone and asks the user', () async {
        var constructed = 0;
        final quarantined = <String>[];
        final noticed = <String>[];

        await expectLater(
          flutterMatrixSdkDatabaseBuilder(
            'a',
            construct: (name) async {
              constructed++;
              throw entry.value;
            },
            quarantine: (name) async => quarantined.add(name),
            markQuarantined: (name) async => noticed.add(name),
          ),
          throwsA(isA<DatabaseOpenFailedException>()),
        );

        expect(constructed, 1);
        expect(quarantined, isEmpty);
        expect(noticed, isEmpty);
      });
    }

    test('a failing quarantine fails closed and deletes nothing', () async {
      var constructed = 0;

      await expectLater(
        flutterMatrixSdkDatabaseBuilder(
          'a',
          construct: (name) async {
            constructed++;
            throw sqliteError(11);
          },
          quarantine: (name) async => throw const FileSystemException('x'),
          markQuarantined: (name) async => fail('nothing was moved'),
        ),
        throwsA(isA<DatabaseOpenFailedException>()),
      );

      expect(constructed, 1);
    });

    test('a failing notice flag does not stop the retry', () async {
      var constructed = 0;

      final result = await flutterMatrixSdkDatabaseBuilder(
        'a',
        construct: (name) async {
          if (constructed++ == 0) throw sqliteError(11);
          return _FakeDatabase();
        },
        quarantine: (name) async {},
        markQuarantined: (name) async => throw StateError('prefs'),
      );

      expect(result, isA<_FakeDatabase>());
    });

    test('a key error on the retry is still a key error', () async {
      var constructed = 0;

      await expectLater(
        flutterMatrixSdkDatabaseBuilder(
          'a',
          construct: (name) async {
            if (constructed++ == 0) throw sqliteError(11);
            throw DatabaseKeyUnavailableException(name, 'x');
          },
          quarantine: (name) async {},
          markQuarantined: (name) async {},
        ),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );
    });
  });

  group('setAccountDatabaseAside', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('db_aside_test'));

    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> path(String name) async => '${dir.path}/$name.sqlite';

    test('moves one account aside and keeps its bytes, the others stay '
        '(B1)', () async {
      File('${dir.path}/a.sqlite').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/a.sqlite-wal').writeAsBytesSync([4]);
      File('${dir.path}/b.sqlite').writeAsBytesSync([9]);

      await setAccountDatabaseAside('a', databasePath: path);

      expect(File('${dir.path}/a.sqlite').existsSync(), isFalse);
      expect(File('${dir.path}/a.sqlite.quarantine-1').readAsBytesSync(), [
        1,
        2,
        3,
      ]);
      expect(File('${dir.path}/a.sqlite.quarantine-1-wal').existsSync(), true);
      expect(File('${dir.path}/b.sqlite').readAsBytesSync(), [9]);
    });

    test('a failing move throws and deletes nothing (B2)', () async {
      final file = File('${dir.path}/a.sqlite')..writeAsBytesSync([1, 2, 3]);

      await expectLater(
        setAccountDatabaseAside(
          'a',
          databasePath: path,
          rename: (file, target) => throw const FileSystemException('x'),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(file.readAsBytesSync(), [1, 2, 3]);
    });

    test('a confirmed set-aside never prunes an older copy (F4)', () async {
      for (var i = 1; i <= 3; i++) {
        File('${dir.path}/a.sqlite').writeAsBytesSync([i]);
        await setAccountDatabaseAside('a', databasePath: path);
      }

      expect(
        dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort(),
        [
          'a.sqlite.quarantine-1',
          'a.sqlite.quarantine-2',
          'a.sqlite.quarantine-3',
        ],
      );
    });

    test('does not mark the damaged-data notice, nothing was damaged '
        '(B3)', () async {
      File('${dir.path}/a.sqlite').writeAsBytesSync([1]);

      await setAccountDatabaseAside('a', databasePath: path);

      expect(AppSettings.databaseQuarantinedClients.value, isEmpty);
    });
  });

  group('resetLocalDatabases', () {
    late Directory dir;
    late Directory cache;
    final storage = <String, String>{};
    final calls = <String>[];

    setUp(() {
      dir = Directory.systemTemp.createTempSync('db_reset_test');
      cache = Directory('${dir.path}/cache')..createSync();
      storage
        ..clear()
        ..['database_password'] = 'old-key';
      calls.clear();
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, (call) async {
            calls.add(call.method);
            final arguments = call.arguments as Map;
            final key = arguments['key'] as String?;
            switch (call.method) {
              case 'read':
                return storage[key];
              case 'write':
                storage[key!] = arguments['value'] as String;
                return null;
              case 'delete':
                storage.remove(key);
                return null;
              case 'readAll':
                return Map<String, String>.of(storage);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
      dir.deleteSync(recursive: true);
    });

    List<File> databaseFiles(String name) => [
      for (final suffix in ['', '-wal', '-shm', '-journal'])
        File('${dir.path}/$name.sqlite$suffix')..writeAsBytesSync([9, 8, 7]),
    ];

    late Directory tempDir;
    late Directory shareDir;

    Future<Set<ResetStep>> reset(
      List<String> names, {
      Future<bool> Function(Iterable<String>)? purgeSecrets,
      Future<Directory?> Function()? fileStorage,
      Future<String?> Function()? sharedRoot,
    }) {
      tempDir = Directory('${dir.path}/tmp')..createSync(recursive: true);
      shareDir = Directory('${dir.path}/share')..createSync(recursive: true);
      return resetLocalDatabases(
        names,
        databasePath: (name) async => '${dir.path}/$name.sqlite',
        fileStorage: fileStorage ?? () async => cache,
        tempStorage: () async => tempDir,
        sharedRoot: sharedRoot ?? () async => shareDir.path,
        isMobile: () => true,
        purgeSecrets: purgeSecrets,
      );
    }

    test('removes the key, every database file and the media cache', () async {
      final files = [...databaseFiles('a'), ...databaseFiles('b')];
      final other = File('${dir.path}/other.sqlite')..writeAsBytesSync([1]);
      File('${cache.path}/media').writeAsBytesSync([1, 2, 3]);

      await reset(['a', 'b']);

      expect(files.where((f) => f.existsSync()), isEmpty);
      expect(cache.existsSync(), isFalse);
      expect(storage, isEmpty);
      expect(other.existsSync(), isTrue);
    });

    test('removes quarantined copies of the reset databases only', () async {
      File('${dir.path}/a.sqlite.quarantine-5').writeAsBytesSync([1]);
      File('${dir.path}/a.sqlite.quarantine-5-wal').writeAsBytesSync([1]);
      File('${dir.path}/a.sqlite.quarantine-6').writeAsBytesSync([1]);
      final other = File('${dir.path}/other.sqlite.quarantine-5')
        ..writeAsBytesSync([1]);

      await reset(['a']);

      expect(
        dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort(),
        ['other.sqlite.quarantine-5'],
      );
      expect(other.existsSync(), isTrue);
    });

    test('a complete reset reports nothing left over (D1)', () async {
      databaseFiles('a');

      expect(await reset(['a']), isEmpty);
    });

    test('a failed secret purge is reported while the files still go '
        '(D2)', () async {
      final files = databaseFiles('a');

      final failed = await reset(['a'], purgeSecrets: (_) async => false);

      expect(failed, {ResetStep.secrets});
      expect(files.where((f) => f.existsSync()), isEmpty);
    });

    test('a throwing secret purge is reported too', () async {
      final failed = await reset([
        'a',
      ], purgeSecrets: (_) async => throw StateError('x'));

      expect(failed, {ResetStep.secrets});
    });

    test('a media cache that cannot be removed is reported (D3)', () async {
      databaseFiles('a');

      final failed = await reset([
        'a',
      ], fileStorage: () async => throw const FileSystemException('x'));

      expect(failed, {ResetStep.mediaCache});
      expect(File('${dir.path}/a.sqlite').existsSync(), isFalse);
    });

    test('the app temp directory and the shared files go, other cache '
        'entries stay (D6)', () async {
      databaseFiles('a');
      final sibling = File('${dir.path}/plugin_copy')..writeAsBytesSync([1]);
      File('${dir.path}/tmp/voice_message_1.opus').createSync(recursive: true);
      File('${dir.path}/share/uuid/photo.jpg').createSync(recursive: true);
      Directory('${dir.path}/tmp').createSync(recursive: true);

      final failed = await reset(['a']);

      expect(failed, isEmpty);
      expect(tempDir.existsSync(), isFalse);
      expect(shareDir.existsSync(), isFalse);
      expect(sibling.existsSync(), isTrue);
    });

    test('a symlinked share root is left alone and its target survives '
        '(F1)', () async {
      databaseFiles('a');
      final target = Directory('${dir.path}/victim')..createSync();
      final precious = File('${target.path}/documents.txt')
        ..writeAsStringSync('keep');
      final link = Link('${dir.path}/receive_sharing_intent')
        ..createSync(target.path);

      final failed = await reset(['a'], sharedRoot: () async => link.path);

      expect(failed, isEmpty);
      expect(precious.readAsStringSync(), 'keep');
      expect(target.existsSync(), isTrue);
      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    });

    test('the production share root is the unresolved path (F1)', () {
      final source = File(
        'lib/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/'
        'builder.dart',
      ).readAsStringSync();

      expect(source, contains('sharedRoot = sharedMediaRootPath'));
    });

    test('a desktop never sweeps the share root (F1)', () async {
      databaseFiles('a');
      final share = Directory('${dir.path}/share')..createSync();
      final shared = File('${share.path}/photo.jpg')..writeAsBytesSync([1]);

      await resetLocalDatabases(
        ['a'],
        databasePath: (name) async => '${dir.path}/$name.sqlite',
        fileStorage: () async => cache,
        tempStorage: () async => null,
        sharedRoot: () async => share.path,
        purgeSecrets: (_) async => true,
      );

      expect(shared.existsSync(), isTrue);
    });

    test(
      'removes the sessions, cached secrets and orphans, keeps the app lock',
      () async {
        storage.addAll({
          'client_data_a': jsonEncode({
            'user_id': '@a:example.org',
            'token': 't',
          }),
          'client_data_b': jsonEncode({'user_id': '@b:example.org'}),
          'client_data_other': 'keep',
          for (final type in cacheTypes) ...{
            'ssss_cache_a_$type': 'secret',
            'ssss_cache_b_$type': 'secret',
            'ssss_cache_other_$type': 'keep',
          },
          'FluffyChat_session_backup_a': 'backup',
          'FluffyChat_session_backup_b': 'backup',
          'FluffyChat_session_backup_other': 'keep',
          'ssss_recovery_key_@a:example.org': 'recovery',
          'ssss_recovery_key_@b:example.org': 'recovery',
          'ssss_recovery_key_@other:example.org': 'keep',
          'com.swovo.odango.app_lock': '1234',
        });

        await reset(['a', 'b']);

        expect(storage.keys.toSet(), {'com.swovo.odango.app_lock'});
      },
    );

    test('a corrupt session entry does not stop the reset', () async {
      storage['client_data_a'] = 'not json';
      databaseFiles('a');

      await reset(['a']);

      expect(storage.containsKey('client_data_a'), isFalse);
      expect(File('${dir.path}/a.sqlite').existsSync(), isFalse);
    });

    test('a missing file does not stop the reset', () async {
      databaseFiles('b');

      await reset(['missing', 'b']);

      expect(File('${dir.path}/b.sqlite').existsSync(), isFalse);
      expect(storage, isEmpty);
    });

    test('the next start proceeds normally and keeps working', () async {
      final file = File('${dir.path}/a.sqlite')
        ..writeAsBytesSync(List.filled(64, 200));
      Future<DatabaseFileState> state() => databaseFileState(file);

      await expectLater(
        getDatabaseCipher('a', databaseState: state),
        completion('old-key'),
      );
      storage.remove('database_password');
      await expectLater(
        getDatabaseCipher('a', databaseState: state),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );

      await reset(['a']);

      final first = await getDatabaseCipher('a', databaseState: state);
      expect(first, isNotNull);
      expect(await getDatabaseCipher('a', databaseState: state), first);
      expect(calls.last, 'read');
    });
  });
}
