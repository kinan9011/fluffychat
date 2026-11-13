// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    secureStorageCalls.clear();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
    mockSecureStorage('fake-password');
    await getDatabaseCipher();
    secureStorageCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test(
    'unavailable secure storage opens unencrypted and sets the flag',
    () async {
      expect(AppSettings.databaseUnencrypted.value, isFalse);

      final cipher = await getDatabaseCipher();

      expect(cipher, isNull);
      expect(AppSettings.databaseUnencrypted.value, isTrue);
    },
  );

  test('a new failure shows the notice again after it was dismissed', () async {
    await AppSettings.databaseUnencryptedNoticeDismissed.setItem(true);
    await markDatabaseEncryption(isEncrypted: true);
    expect(AppSettings.databaseUnencrypted.value, isFalse);
    expect(AppSettings.databaseUnencryptedNoticeDismissed.value, isFalse);

    await markDatabaseEncryption(isEncrypted: false);
    expect(AppSettings.databaseUnencrypted.value, isTrue);
    expect(AppSettings.databaseUnencryptedNoticeDismissed.value, isFalse);
  });

  test('encryption working again clears the warning flags', () async {
    await AppSettings.databaseUnencrypted.setItem(true);
    await AppSettings.noEncryptionWarningShown.setItem(true);

    await markDatabaseEncryption(isEncrypted: true);

    expect(AppSettings.databaseUnencrypted.value, isFalse);
    expect(AppSettings.noEncryptionWarningShown.value, isFalse);
  });

  test('a readable key returns the cipher and clears the flag', () async {
    await AppSettings.databaseUnencrypted.setItem(true);
    mockSecureStorage('fake-password');

    expect(await getDatabaseCipher(), 'fake-password');
    expect(AppSettings.databaseUnencrypted.value, isFalse);
  });

  Future<void> throwingMarker({required bool isEncrypted}) async =>
      throw StateError('prefs write failed');

  test('failing to store the state never deletes the database key', () async {
    mockSecureStorage('fake-password');

    final cipher = await getDatabaseCipher(markEncryption: throwingMarker);

    expect(cipher, 'fake-password');
    expect(secureStorageCalls, isNot(contains('delete')));
  });

  test('failing to store the state does not break the fallback', () async {
    expect(await getDatabaseCipher(markEncryption: throwingMarker), isNull);
  });

  test('the unencrypted state survives a failing flag write', () async {
    expect(await getDatabaseCipher(markEncryption: throwingMarker), isNull);

    expect(AppSettings.databaseUnencrypted.value, isFalse);
    expect(isDatabaseUnencrypted, isTrue);
  });

  test('an encrypted open clears the in-memory state again', () async {
    await getDatabaseCipher(markEncryption: throwingMarker);
    mockSecureStorage('fake-password');

    await getDatabaseCipher();

    expect(isDatabaseUnencrypted, isFalse);
  });
}
