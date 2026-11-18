// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/encryption.dart' show cacheTypes;
import 'package:matrix/matrix.dart';

typedef SecretStore = ({
  Future<Map<String, String>> Function() readAll,
  Future<void> Function(String key) delete,
});

const _databaseKey = 'database_password';

/// The keys of the database, the session, cached cross-signing secrets, the
/// session backup and the stored recovery key. The app lock settings are not
/// among them.
bool isAccountSecretKey(String key) =>
    key == _databaseKey ||
    key.startsWith('client_data_') ||
    key.startsWith('ssss_cache_') ||
    key.startsWith('ssss_recovery_key_') ||
    key.contains('_session_backup_');

SecretStore _storeOf(FlutterSecureStorage storage) =>
    (readAll: storage.readAll, delete: (key) => storage.delete(key: key));

List<SecretStore> productionSecretStores() => [
  _storeOf(createSecureStorage(iOptions: iosOptions)),
  _storeOf(createSecureStorage()),
];

/// Only for the user-confirmed reset, and only used after the plain purge
/// failed: with `resetOnError` the Android plugin repairs a keystore that
/// cannot be initialised by wiping it, which also removes the app lock PIN.
SecretStore? productionRepairStore() =>
    PlatformInfos.isAndroid ? _storeOf(createRepairingSecureStorage()) : null;

Future<bool> _purge(SecretStore store, Set<String> known) async {
  var complete = true;
  final keys = {...known};
  try {
    keys.addAll((await store.readAll()).keys.where(isAccountSecretKey));
  } catch (e) {
    Logs().w('Unable to list the stored secrets', e.runtimeType);
    complete = false;
  }
  for (final key in keys) {
    try {
      await store.delete(key);
    } catch (e) {
      Logs().w('Unable to delete a stored secret', e.runtimeType);
      complete = false;
    }
  }
  return complete;
}

/// Deletes the secrets of [clientNames] and every other account secret found
/// in each store, so that nothing of a removed account can bring a session
/// back. Returns false when a secret may be left.
Future<bool> purgeStoredSecrets(
  Iterable<String> clientNames, {
  required List<SecretStore> stores,
  SecretStore? repair,
}) async {
  final known = {
    _databaseKey,
    for (final name in clientNames) ...[
      'client_data_$name',
      for (final type in cacheTypes) 'ssss_cache_${name}_$type',
      '${AppSettings.applicationName.value}_session_backup_$name',
    ],
  };
  var complete = true;
  for (final store in stores) {
    complete = await _purge(store, known) && complete;
  }
  if (complete || repair == null) return complete;
  return _purge(repair, known);
}
