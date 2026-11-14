// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart' show cacheTypes;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'cipher.dart';
import 'database_file_state.dart';
import 'database_open_error.dart';
import 'database_quarantine.dart';
import 'database_quarantine_notice.dart';

Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(
  String clientName, {
  @visibleForTesting
  Future<DatabaseApi> Function(String clientName) construct =
      _constructDatabase,
  @visibleForTesting
  Future<void> Function(String clientName) quarantine = _quarantineDatabaseFile,
  @visibleForTesting
  Future<void> Function(String clientName) markQuarantined =
      markDatabaseQuarantined,
}) async {
  try {
    return await construct(clientName);
  } on DatabaseKeyUnavailableException {
    rethrow;
  } on DatabaseOpenFailedException {
    rethrow;
  } catch (e, s) {
    // Deny by default: only a proven corruption moves the file; anything
    // else (full disk, lock contention, I/O error, wrong key...) leaves it
    // untouched and goes to the Retry / Reset page.
    if (classifyDatabaseOpenError(e) != DatabaseOpenFailure.corrupt) {
      Logs().w('Unable to open the database, leaving it untouched', e, s);
      throw DatabaseOpenFailedException(clientName, e);
    }
    Logs().wtf('The database is damaged!', e, s);

    try {
      // Send error notification:
      final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      if (!PlatformInfos.isIOS) {
        ClientManager.sendInitNotification(
          l10n.initAppError,
          e.toString(),
        ).catchError(
          (Object e, StackTrace s) =>
              Logs().e('Unable to send error notification', e, s),
        );
      }
    } catch (e, s) {
      Logs().e('Unable to send error notification', e, s);
    }

    try {
      await quarantine(clientName);
    } catch (e, s) {
      Logs().w('Unable to move the damaged database aside', e, s);
      throw DatabaseOpenFailedException(clientName, e);
    }
    try {
      await markQuarantined(clientName);
    } catch (e, s) {
      Logs().w('Unable to store the quarantine notice', e, s);
    }

    try {
      return await construct(clientName);
    } on DatabaseKeyUnavailableException {
      rethrow;
    } catch (e) {
      throw DatabaseOpenFailedException(clientName, e);
    }
  }
}

/// Not on the web: there the database is IndexedDB, which is left as it is.
Future<void> _quarantineDatabaseFile(String clientName) async {
  if (kIsWeb) return;
  await quarantineDatabase(await _getDatabasePath(clientName));
}

Future<Directory?> getFileStorageLocation() async {
  try {
    late final Directory temporaryDirectory;
    if (PlatformInfos.isIOS) {
      final containerPath = await PathProviderFoundation().getContainerPath(
        appGroupIdentifier: 'group.im.fluffychat.app',
      );
      temporaryDirectory = Directory(containerPath!);
    } else if (PlatformInfos.isLinux) {
      temporaryDirectory = await getApplicationCacheDirectory();
    } else {
      temporaryDirectory = await getTemporaryDirectory();
    }
    return await Directory(
      join(temporaryDirectory.path, 'fluffychat_download_cache'),
    ).create(recursive: true);
  } on MissingPlatformDirectoryException catch (_) {
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }
  return null;
}

Future<MatrixSdkDatabase> _constructDatabase(String clientName) async {
  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    markWebDatabaseUnencrypted(clientName);
    return await MatrixSdkDatabase.init(clientName);
  }

  final path = await _getDatabasePath(clientName);

  // import the SQLite / SQLCipher shared objects / dynamic libraries
  final factory = createDatabaseFactoryFfi();

  // required for [getDatabasesPath]
  databaseFactory = factory;

  // migrate from potential previous SQLite database path to current one
  await _migrateLegacyLocation(path, clientName);

  final cipher = await getDatabaseCipher(
    clientName,
    databaseState: () => databaseFileState(File(path)),
  );

  final fileStorageLocation = await getFileStorageLocation();

  // in case we got a cipher, we use the encryption helper
  // to manage SQLite encryption
  final helper = cipher == null
      ? null
      : SQfLiteEncryptionHelper(factory: factory, path: path, cipher: cipher);

  // check whether the DB is already encrypted and otherwise do so
  await helper?.ensureDatabaseFileEncrypted();

  final openDatabaseOptions = OpenDatabaseOptions(
    version: 1,
    // most important : apply encryption when opening the DB
    onConfigure: (db) =>
        helper?.applyPragmaKey(db, ensureIncrementalAutoVacuum: true),
  );

  final database = await factory.openDatabase(
    path,
    options: openDatabaseOptions,
  );

  final secureStorage = cipher == null
      ? null
      : createSecureStorage(iOptions: iosOptions);

  return await MatrixSdkDatabase.init(
    clientName,
    database: database,
    maxFileSize: 1000 * 1000 * 10,
    fileStorageLocation: fileStorageLocation?.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
    secureStorage: secureStorage == null
        ? null
        : (
            read: (key) => secureStorage.read(key: key),
            write: (key, value) => secureStorage.write(key: key, value: value),
            delete: (key) => secureStorage.delete(key: key),
          ),
  );
}

/// What the SDK and the app keep in the secure storage for one account: the
/// session (tokens, device key pickle), cached cross-signing secrets, the
/// session backup and the stored recovery key.
Future<void> _deleteAccountSecrets(String clientName) async {
  final sdkStorage = createSecureStorage(iOptions: iosOptions);
  final appStorage = createSecureStorage();
  final keys = <String>[
    'client_data_$clientName',
    for (final type in cacheTypes) 'ssss_cache_${clientName}_$type',
  ];
  try {
    final clientData = await sdkStorage.read(key: 'client_data_$clientName');
    final userId = clientData == null
        ? null
        : (jsonDecode(clientData) as Map)['user_id'];
    if (userId is String) {
      await appStorage.delete(key: 'ssss_recovery_key_$userId');
    }
  } catch (e, s) {
    Logs().w('Unable to look up the stored recovery key', e, s);
  }
  for (final key in keys) {
    try {
      await sdkStorage.delete(key: key);
    } catch (e, s) {
      Logs().w('Unable to delete a stored secret', e, s);
    }
  }
  try {
    await InitWithRestoreExtension.deleteSessionBackup(clientName);
  } catch (e, s) {
    Logs().w('Unable to delete the session backup', e, s);
  }
}

/// Deletes everything the app stored for its accounts on this device: the
/// shared database key, every database with its SQLite side files and
/// quarantined copies, the sessions and cached secrets in the secure storage,
/// and the decrypted media cache. The app lock settings stay.
Future<void> resetLocalDatabases(
  Iterable<String> clientNames, {
  @visibleForTesting
  Future<String> Function(String clientName) databasePath = _getDatabasePath,
  @visibleForTesting
  Future<Directory?> Function() fileStorage = getFileStorageLocation,
}) async {
  await deleteDatabaseKey();
  for (final clientName in clientNames) {
    await _deleteAccountSecrets(clientName);
    try {
      final path = await databasePath(clientName);
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      await deleteQuarantinedDatabases(path);
    } catch (e, s) {
      Logs().w('Unable to delete local database', e, s);
    }
  }
  try {
    final cache = await fileStorage();
    if (cache != null && await cache.exists()) {
      await cache.delete(recursive: true);
    }
  } catch (e, s) {
    Logs().w('Unable to delete the media cache', e, s);
  }
}

Future<String> _getDatabaseDirectory() async {
  if (PlatformInfos.isIOS) {
    final containerPath = await PathProviderFoundation().getContainerPath(
      appGroupIdentifier: 'group.im.fluffychat.app',
    );
    if (containerPath == null) {
      Logs().w('No container path found for iOS app!');
      return (await getLibraryDirectory()).path;
    }
    return containerPath;
  }
  if (PlatformInfos.isMacOS) {
    return (await getLibraryDirectory()).path;
  }
  return (await getApplicationSupportDirectory()).path;
}

Future<String> _getDatabasePath(String clientName) async {
  final databaseDirectory = await _getDatabaseDirectory();

  return join(databaseDirectory, '$clientName.sqlite');
}

Future<void> _migrateLegacyLocation(
  String sqlFilePath,
  String clientName,
) async {
  final oldPath = PlatformInfos.isDesktop
      ? (await getApplicationSupportDirectory()).path
      : PlatformInfos.isIOS
      ? (await getLibraryDirectory()).path
      : await getDatabasesPath();

  final oldFilePath = join(oldPath, '$clientName.sqlite');
  if (oldFilePath == sqlFilePath) return;

  final maybeOldFile = File(oldFilePath);
  if (await maybeOldFile.exists()) {
    Logs().i(
      'Migrate legacy location for database from "$oldFilePath" to "$sqlFilePath"',
    );
    await maybeOldFile.copy(sqlFilePath);
    await maybeOldFile.delete();
  }
}
