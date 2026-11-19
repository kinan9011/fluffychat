// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart' show cacheTypes;
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/account_secret_purge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store {
  _Store(this.data, {this.readAllFails = false, this.deleteFails = false});

  final Map<String, String> data;
  final bool readAllFails;
  final bool deleteFails;
  final deleted = <String>[];
  var readAlls = 0;

  SecretStore get store => (
    readAll: () async {
      readAlls++;
      if (readAllFails) throw StateError('locked');
      return Map.of(data);
    },
    delete: (key) async {
      deleted.add(key);
      if (deleteFails) throw StateError('locked');
      data.remove(key);
    },
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Map<String, String> filled() => {
    'database_password': 'key',
    'client_data_a': '{}',
    'client_data_gone': '{}',
    for (final type in cacheTypes) 'ssss_cache_a_$type': 's',
    'FluffyChat_session_backup_a': 'b',
    'FluffyChat_session_backup_old': 'b',
    'ssss_recovery_key_@gone:example.org': 'r',
    'com.swovo.odango.app_lock': '1234',
    'com.swovo.odango.use_biometrics': 'true',
    'unrelated': 'keep',
  };

  test('isAccountSecretKey knows the account keys and not the app lock', () {
    for (final key in [
      'database_password',
      'client_data_x',
      'ssss_cache_x_m.cross_signing.master',
      'ssss_recovery_key_@u:example.org',
      'FluffyChat_session_backup_x',
    ]) {
      expect(isAccountSecretKey(key), isTrue, reason: key);
    }
    for (final key in [
      'com.swovo.odango.app_lock',
      'com.swovo.odango.use_biometrics',
      'unrelated',
    ]) {
      expect(isAccountSecretKey(key), isFalse, reason: key);
    }
  });

  test('removes the secrets of the named accounts and the orphans of removed '
      'ones, keeps the app lock (D4)', () async {
    final store = _Store(filled());

    final ok = await purgeStoredSecrets(['a'], stores: [store.store]);

    expect(ok, isTrue);
    expect(store.data.keys.toSet(), {
      'com.swovo.odango.app_lock',
      'com.swovo.odango.use_biometrics',
      'unrelated',
    });
  });

  test('a store that cannot be read is reported and the known keys are '
      'still tried', () async {
    final store = _Store(filled(), readAllFails: true);

    final ok = await purgeStoredSecrets(['a'], stores: [store.store]);

    expect(ok, isFalse);
    expect(store.deleted, contains('client_data_a'));
    expect(store.deleted, contains('database_password'));
  });

  test('every store is attempted even if the first one fails (D7)', () async {
    final broken = _Store(filled(), readAllFails: true, deleteFails: true);
    final healthy = _Store(filled());

    final ok = await purgeStoredSecrets(
      ['a'],
      stores: [broken.store, healthy.store],
    );

    expect(ok, isFalse);
    expect(healthy.data.keys.where(isAccountSecretKey), isEmpty);
  });

  test('a failed purge is repaired by the repair store and reported as '
      'done (D5)', () async {
    final broken = _Store(filled(), readAllFails: true, deleteFails: true);
    final repair = _Store(filled());

    final ok = await purgeStoredSecrets(
      ['a'],
      stores: [broken.store],
      repair: repair.store,
    );

    expect(ok, isTrue);
    expect(repair.data.keys.where(isAccountSecretKey), isEmpty);
  });

  test('without a repair store a failed purge stays failed', () async {
    final broken = _Store(filled(), deleteFails: true);

    expect(await purgeStoredSecrets(['a'], stores: [broken.store]), isFalse);
  });

  test('a repair that fails too is reported', () async {
    final broken = _Store(filled(), deleteFails: true);
    final repair = _Store(filled(), deleteFails: true);

    final ok = await purgeStoredSecrets(
      ['a'],
      stores: [broken.store],
      repair: repair.store,
    );

    expect(ok, isFalse);
  });

  test(
    'a healthy purge never touches the repair store or the PIN (D8)',
    () async {
      final store = _Store(filled());
      final repair = _Store(filled());

      final ok = await purgeStoredSecrets(
        ['a'],
        stores: [store.store],
        repair: repair.store,
      );

      expect(ok, isTrue);
      expect(repair.readAlls, 0);
      expect(repair.deleted, isEmpty);
      expect(store.data['com.swovo.odango.app_lock'], '1234');
    },
  );
}
