// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_file_state.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

const _passwordStorageKey = 'database_password';

const iosOptions = IOSOptions(
  groupId: 'group.im.fluffychat.app',
  accessibility: .first_unlock,
);

/// The system key store failed for a database that already exists. The key
/// and the database must stay untouched until the user decides what to do.
class DatabaseKeyUnavailableException implements Exception {
  final String clientName;
  final Object error;

  const DatabaseKeyUnavailableException(this.clientName, this.error);

  @override
  String toString() => 'DatabaseKeyUnavailableException';
}

@visibleForTesting
final unencryptedClientsThisSession = <String>{};

/// Also true when persisting the state failed, so the notice is never lost.
bool get isDatabaseUnencrypted {
  if (unencryptedClientsThisSession.isNotEmpty) return true;
  final persisted = AppSettings.databaseUnencryptedClients.value;
  if (persisted.isEmpty) return false;
  try {
    final current =
        AppSettings.store.getStringList(ClientManager.clientNamespace) ?? [];
    return persisted.any(current.contains);
  } catch (_) {
    return false;
  }
}

typedef MarkDatabaseEncryption =
    Future<void> Function(String clientName, {required bool isEncrypted});

/// The web database is IndexedDB, which this app cannot encrypt.
void markWebDatabaseUnencrypted(String clientName) =>
    unencryptedClientsThisSession.add(clientName);

Future<void> deleteDatabaseKey() async {
  try {
    await createSecureStorage(
      iOptions: iosOptions,
    ).delete(key: _passwordStorageKey, iOptions: iosOptions);
  } catch (e, s) {
    Logs().w('Unable to delete database key', e, s);
  }
}

Future<DatabaseFileState> _stateOrEncrypted(
  Future<DatabaseFileState> Function() databaseState,
) async {
  try {
    return await databaseState();
  } catch (e, s) {
    Logs().w('Unable to check the existing database', e, s);
    return DatabaseFileState.encrypted;
  }
}

/// Never deletes the key or the database. If the key cannot be read, a
/// plaintext or missing database is opened unencrypted as before; an
/// encrypted database that cannot be unlocked throws
/// [DatabaseKeyUnavailableException] so that the user decides.
Future<String?> getDatabaseCipher(
  String clientName, {
  required Future<DatabaseFileState> Function() databaseState,
  @visibleForTesting
  MarkDatabaseEncryption markEncryption = markDatabaseEncryption,
}) async {
  String? password;

  try {
    final storage = createSecureStorage(iOptions: iosOptions);
    password = await storage.read(
      key: _passwordStorageKey,
      iOptions: iosOptions,
    );
    if (password != null) {
      await _markEncryption(markEncryption, clientName, isEncrypted: true);
      return password;
    }

    if (PlatformInfos.isIOS) {
      final legacyStorage = createSecureStorage();
      final legacyPassword = await legacyStorage.read(key: _passwordStorageKey);
      if (legacyPassword != null) {
        Logs().i('Migrate database key location on iOS...');
        await legacyStorage.delete(key: _passwordStorageKey);
        await storage.write(
          key: _passwordStorageKey,
          value: legacyPassword,
          iOptions: iosOptions,
        );
        await _markEncryption(markEncryption, clientName, isEncrypted: true);
        return legacyPassword;
      }
    }

    final state = await _stateOrEncrypted(databaseState);
    if (state == DatabaseFileState.encrypted) {
      throw DatabaseKeyUnavailableException(clientName, 'missing key');
    }

    final rng = Random.secure();
    final list = Uint8List(32);
    list.setAll(0, Iterable.generate(list.length, (i) => rng.nextInt(256)));
    final newPassword = base64UrlEncode(list);
    await storage.write(
      key: _passwordStorageKey,
      value: newPassword,
      iOptions: iosOptions,
    );
    // workaround for if we just wrote to the key and it still doesn't exist
    password = await storage.read(
      key: _passwordStorageKey,
      iOptions: iosOptions,
    );
    if (password == null) throw MissingPluginException();
    await _markEncryption(markEncryption, clientName, isEncrypted: true);
    return password;
  } on MissingPluginException catch (e) {
    createSecureStorage(
      iOptions: iosOptions,
    ).delete(key: _passwordStorageKey, iOptions: iosOptions).catchError((_) {});
    Logs().w('Database encryption is not supported on this platform', e);
    await _markEncryption(markEncryption, clientName, isEncrypted: false);
    _sendNoEncryptionWarning(e);
  } on DatabaseKeyUnavailableException {
    rethrow;
  } catch (e, s) {
    Logs().w('Unable to read database key', e, s);
    final state = await _stateOrEncrypted(databaseState);
    if (state == DatabaseFileState.encrypted) {
      throw DatabaseKeyUnavailableException(clientName, e);
    }
    await _markEncryption(markEncryption, clientName, isEncrypted: false);
    _sendNoEncryptionWarning(e);
  }
  return null;
}

Future<void> markDatabaseEncryption(
  String clientName, {
  required bool isEncrypted,
}) async {
  final names = AppSettings.databaseUnencryptedClients.value;
  if (isEncrypted) {
    if (names.contains(clientName)) {
      await AppSettings.databaseUnencryptedClients.setItem(
        names.where((name) => name != clientName).toList(),
      );
    }
    if (AppSettings.databaseUnencryptedClients.value.isNotEmpty) return;
    if (AppSettings.noEncryptionWarningShown.value) {
      await AppSettings.noEncryptionWarningShown.setItem(false);
    }
    if (AppSettings.databaseUnencryptedNoticeDismissed.value) {
      await AppSettings.databaseUnencryptedNoticeDismissed.setItem(false);
    }
    return;
  }
  if (names.contains(clientName)) return;
  await AppSettings.databaseUnencryptedClients.setItem([...names, clientName]);
  await AppSettings.databaseUnencryptedNoticeDismissed.setItem(false);
}

/// Bookkeeping for the UI must never throw into the key handling above: an
/// exception there would reach the catch blocks that handle the database key.
Future<void> _markEncryption(
  MarkDatabaseEncryption mark,
  String clientName, {
  required bool isEncrypted,
}) async {
  isEncrypted
      ? unencryptedClientsThisSession.remove(clientName)
      : unencryptedClientsThisSession.add(clientName);
  try {
    await mark(clientName, isEncrypted: isEncrypted);
  } catch (e, s) {
    Logs().e('Unable to store database encryption state', e, s);
  }
}

Future<void> _sendNoEncryptionWarning(Object exception) async {
  final isStored = AppSettings.noEncryptionWarningShown.value;

  if (isStored == true) return;

  try {
    final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
    await ClientManager.sendInitNotification(
      l10n.noDatabaseEncryption,
      exception.toString(),
    );
  } catch (e, s) {
    Logs().w('Unable to send no database encryption notification', e, s);
  }

  await AppSettings.noEncryptionWarningShown.setItem(true);
}
