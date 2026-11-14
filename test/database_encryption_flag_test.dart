// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n_en.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_file_state.dart';
import 'package:fluffychat/widgets/database_unencrypted_warning.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

Future<DatabaseFileState> _noDatabase() async => DatabaseFileState.none;

Future<DatabaseFileState> _plaintextDatabase() async =>
    DatabaseFileState.plaintext;

Future<DatabaseFileState> _encryptedDatabase() async =>
    DatabaseFileState.encrypted;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageCalls = <String>[];

  void mockSecureStorage(String? password) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          secureStorageCalls.add(call.method);
          return call.method == 'read' ? password : null;
        });
  }

  void mockStatefulStorage(Map<String, String> storage) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          secureStorageCalls.add(call.method);
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
          }
          return null;
        });
  }

  void mockKeystoreError() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          secureStorageCalls.add(call.method);
          if (call.method == 'read') {
            throw PlatformException(code: 'keystore');
          }
          return null;
        });
  }

  void mockMissingPlugin() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          secureStorageCalls.add(call.method);
          throw MissingPluginException();
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    secureStorageCalls.clear();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
    unencryptedClientsThisSession.clear();
    await AppSettings.store.setStringList(ClientManager.clientNamespace, [
      'a',
      'b',
    ]);
    secureStorageCalls.clear();
  });

  test(
    'unavailable secure storage opens unencrypted and sets the flag',
    () async {
      mockMissingPlugin();
      expect(AppSettings.databaseUnencryptedClients.value, isEmpty);

      final cipher = await getDatabaseCipher('a', databaseState: _noDatabase);

      expect(cipher, isNull);
      expect(AppSettings.databaseUnencryptedClients.value, ['a']);
      expect(isDatabaseUnencrypted, isTrue);
    },
  );

  test('missing plugin still deletes the key', () async {
    mockMissingPlugin();

    expect(
      await getDatabaseCipher('a', databaseState: _encryptedDatabase),
      isNull,
    );
    expect(secureStorageCalls, contains('delete'));
  });

  test('a keystore error never deletes the key', () async {
    mockKeystoreError();

    await expectLater(
      getDatabaseCipher('a', databaseState: _encryptedDatabase),
      throwsA(isA<DatabaseKeyUnavailableException>()),
    );
    expect(secureStorageCalls, isNot(contains('delete')));
  });

  test('a keystore error without a database falls back unencrypted', () async {
    mockKeystoreError();

    expect(await getDatabaseCipher('a', databaseState: _noDatabase), isNull);
    expect(secureStorageCalls, isNot(contains('delete')));
    expect(isDatabaseUnencrypted, isTrue);
  });

  test('a keystore error with a plaintext database keeps it open', () async {
    mockKeystoreError();

    expect(
      await getDatabaseCipher('a', databaseState: _plaintextDatabase),
      isNull,
    );
    expect(secureStorageCalls, isNot(contains('delete')));
    expect(secureStorageCalls, isNot(contains('write')));
    expect(isDatabaseUnencrypted, isTrue);
    expect(AppSettings.databaseUnencryptedClients.value, ['a']);
  });

  test('a missing key with an encrypted database is an error', () async {
    mockStatefulStorage({});

    await expectLater(
      getDatabaseCipher('a', databaseState: _encryptedDatabase),
      throwsA(isA<DatabaseKeyUnavailableException>()),
    );
    expect(secureStorageCalls, isNot(contains('write')));
    expect(secureStorageCalls, isNot(contains('delete')));
    expect(isDatabaseUnencrypted, isFalse);
  });

  test('a missing key with a plaintext database creates a key', () async {
    final storage = <String, String>{};
    mockStatefulStorage(storage);

    final cipher = await getDatabaseCipher(
      'a',
      databaseState: _plaintextDatabase,
    );

    expect(cipher, isNotNull);
    expect(storage.values, [cipher]);
    expect(isDatabaseUnencrypted, isFalse);
  });

  test('a missing key without a database creates a key', () async {
    final storage = <String, String>{};
    mockStatefulStorage(storage);

    final cipher = await getDatabaseCipher('a', databaseState: _noDatabase);

    expect(cipher, isNotNull);
    expect(storage.values, [cipher]);
  });

  test('a failing database check counts as encrypted', () async {
    mockKeystoreError();

    await expectLater(
      getDatabaseCipher('a', databaseState: () async => throw StateError('x')),
      throwsA(isA<DatabaseKeyUnavailableException>()),
    );
    expect(secureStorageCalls, isNot(contains('delete')));
  });

  test(
    'the key error with an encrypted database is not an unencrypted state',
    () async {
      mockKeystoreError();
      await expectLater(
        getDatabaseCipher('a', databaseState: _encryptedDatabase),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );
      expect(isDatabaseUnencrypted, isFalse);
    },
  );

  test('one encrypted client does not hide another unencrypted one', () async {
    mockMissingPlugin();
    await getDatabaseCipher('a', databaseState: _noDatabase);
    mockSecureStorage('fake-password');
    expect(
      await getDatabaseCipher('b', databaseState: _noDatabase),
      'fake-password',
    );

    expect(isDatabaseUnencrypted, isTrue);
    expect(AppSettings.databaseUnencryptedClients.value, ['a']);
  });

  test('the persisted state is found again in a later session', () async {
    await AppSettings.databaseUnencryptedClients.setItem(['b']);

    expect(isDatabaseUnencrypted, isTrue);
  });

  test('a removed account no longer counts', () async {
    await AppSettings.databaseUnencryptedClients.setItem(['gone']);

    expect(isDatabaseUnencrypted, isFalse);
  });

  test('a web database is unencrypted for the session only', () async {
    markWebDatabaseUnencrypted('w');

    expect(isDatabaseUnencrypted, isTrue);
    expect(AppSettings.databaseUnencryptedClients.value, isEmpty);
  });

  test('a new failure shows the notice again after it was dismissed', () async {
    await AppSettings.databaseUnencryptedNoticeDismissed.setItem(true);
    await markDatabaseEncryption('a', isEncrypted: true);
    expect(AppSettings.databaseUnencryptedClients.value, isEmpty);
    expect(AppSettings.databaseUnencryptedNoticeDismissed.value, isFalse);

    await markDatabaseEncryption('a', isEncrypted: false);
    expect(AppSettings.databaseUnencryptedClients.value, ['a']);
    expect(AppSettings.databaseUnencryptedNoticeDismissed.value, isFalse);
  });

  test('encryption working again clears the warning flags', () async {
    await AppSettings.databaseUnencryptedClients.setItem(['a']);
    await AppSettings.noEncryptionWarningShown.setItem(true);

    await markDatabaseEncryption('a', isEncrypted: true);

    expect(AppSettings.databaseUnencryptedClients.value, isEmpty);
    expect(AppSettings.noEncryptionWarningShown.value, isFalse);
  });

  test('another client still unencrypted keeps the warning flags', () async {
    await AppSettings.databaseUnencryptedClients.setItem(['a', 'b']);
    await AppSettings.noEncryptionWarningShown.setItem(true);

    await markDatabaseEncryption('a', isEncrypted: true);

    expect(AppSettings.databaseUnencryptedClients.value, ['b']);
    expect(AppSettings.noEncryptionWarningShown.value, isTrue);
  });

  test('a readable key returns the cipher and clears the flag', () async {
    await AppSettings.databaseUnencryptedClients.setItem(['a']);
    mockSecureStorage('fake-password');

    expect(
      await getDatabaseCipher('a', databaseState: _noDatabase),
      'fake-password',
    );
    expect(AppSettings.databaseUnencryptedClients.value, isEmpty);
  });

  Future<void> throwingMarker(
    String clientName, {
    required bool isEncrypted,
  }) async => throw StateError('prefs write failed');

  test('failing to store the state never deletes the database key', () async {
    mockSecureStorage('fake-password');

    final cipher = await getDatabaseCipher(
      'a',
      databaseState: _noDatabase,
      markEncryption: throwingMarker,
    );

    expect(cipher, 'fake-password');
    expect(secureStorageCalls, isNot(contains('delete')));
  });

  test('failing to store the state does not break the fallback', () async {
    mockMissingPlugin();
    expect(
      await getDatabaseCipher(
        'a',
        databaseState: _noDatabase,
        markEncryption: throwingMarker,
      ),
      isNull,
    );
  });

  test('the unencrypted state survives a failing flag write', () async {
    mockMissingPlugin();
    await getDatabaseCipher(
      'a',
      databaseState: _noDatabase,
      markEncryption: throwingMarker,
    );

    expect(AppSettings.databaseUnencryptedClients.value, isEmpty);
    expect(isDatabaseUnencrypted, isTrue);
  });

  test('an encrypted client does not clear another one in memory', () async {
    mockMissingPlugin();
    await getDatabaseCipher(
      'a',
      databaseState: _noDatabase,
      markEncryption: throwingMarker,
    );
    mockSecureStorage('fake-password');
    await getDatabaseCipher(
      'b',
      databaseState: _noDatabase,
      markEncryption: throwingMarker,
    );

    expect(AppSettings.databaseUnencryptedClients.value, isEmpty);
    expect(isDatabaseUnencrypted, isTrue);
  });

  test('an encrypted open clears the in-memory state again', () async {
    mockMissingPlugin();
    await getDatabaseCipher(
      'a',
      databaseState: _noDatabase,
      markEncryption: throwingMarker,
    );
    mockSecureStorage('fake-password');

    await getDatabaseCipher('a', databaseState: _noDatabase);

    expect(isDatabaseUnencrypted, isFalse);
  });

  group('databaseUnencryptedDescription', () {
    final l10n = L10nEn();

    test('web explains the browser storage', () {
      expect(
        databaseUnencryptedDescription(l10n, isWeb: true),
        l10n.databaseNotEncryptedWeb,
      );
    });

    test('linux points to the keyring', () {
      expect(
        databaseUnencryptedDescription(l10n, isWeb: false, isLinux: true),
        contains(l10n.databaseNotEncryptedKeyringHint),
      );
    });

    test('other platforms suggest a restart', () {
      expect(
        databaseUnencryptedDescription(l10n, isWeb: false, isLinux: false),
        contains(l10n.databaseNotEncryptedRestartHint),
      );
    });
  });
}
