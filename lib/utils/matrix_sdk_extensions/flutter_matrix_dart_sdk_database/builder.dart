// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_config.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/app_temp_directory.dart';
import 'package:odango/utils/client_manager.dart';
import 'package:odango/utils/platform_infos.dart';
import 'package:odango/utils/secure_storage.dart';
import 'package:odango/utils/shared_media_filter.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'account_secret_purge.dart';
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
        appGroupIdentifier: AppConfig.appleAppGroupId,
      );
      temporaryDirectory = Directory(containerPath!);
    } else if (PlatformInfos.isLinux) {
      temporaryDirectory = await getApplicationCacheDirectory();
    } else {
      temporaryDirectory = await getTemporaryDirectory();
    }
    return await Directory(
      join(temporaryDirectory.path, 'odango_download_cache'),
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

bool _isMobile() => PlatformInfos.isMobile;

enum ResetStep { secrets, databaseFiles, mediaCache, tempFiles, sharedFiles }

Future<bool> _purgeProductionSecrets(Iterable<String> clientNames) =>
    purgeStoredSecrets(
      clientNames,
      stores: productionSecretStores(),
      repair: productionRepairStore(),
    );

/// Deletes everything the app stored for its accounts on this device: the
/// shared database key, every database with its SQLite side files and
/// quarantined copies, the sessions and cached secrets in the secure storage,
/// the decrypted media cache, the app temp files and, on Android and iOS, the
/// shared files (never through a link). The app lock settings stay. Every step is attempted; the steps that did not finish
/// are returned, an empty set means the reset is complete.
Future<Set<ResetStep>> resetLocalDatabases(
  Iterable<String> clientNames, {
  @visibleForTesting
  Future<String> Function(String clientName) databasePath = _getDatabasePath,
  @visibleForTesting
  Future<Directory?> Function() fileStorage = getFileStorageLocation,
  @visibleForTesting
  Future<Directory?> Function() tempStorage = appTempDirectoryIfExists,
  @visibleForTesting
  Future<String?> Function() sharedRoot = sharedMediaRootPath,
  @visibleForTesting bool Function() isMobile = _isMobile,
  @visibleForTesting
  Future<bool> Function(Iterable<String> clientNames)? purgeSecrets,
}) async {
  final failed = <ResetStep>{};
  Future<void> attempt(ResetStep step, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      Logs().w('Reset step failed: ${step.name}', e.runtimeType);
      failed.add(step);
    }
  }

  await attempt(ResetStep.secrets, () async {
    final done = await (purgeSecrets ?? _purgeProductionSecrets)(clientNames);
    if (!done) failed.add(ResetStep.secrets);
  });
  for (final clientName in clientNames) {
    await attempt(ResetStep.databaseFiles, () async {
      final path = await databasePath(clientName);
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      await deleteQuarantinedDatabases(path);
    });
  }
  await attempt(ResetStep.mediaCache, () async {
    final cache = await fileStorage();
    if (cache != null && await cache.exists()) {
      await cache.delete(recursive: true);
    }
  });
  await attempt(ResetStep.tempFiles, () async {
    await (await tempStorage())?.delete(recursive: true);
  });
  await attempt(ResetStep.sharedFiles, () async {
    if (!isMobile()) return;
    final root = await sharedRoot();
    if (root == null) return;
    if (await FileSystemEntity.isLink(root)) {
      Logs().w('The share root is a link, leaving it alone');
      return;
    }
    final directory = Directory(root);
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return failed;
}

/// L1: the user moves the one account that cannot be opened aside (renamed,
/// bytes kept, no copy pruned, deleted again by logout and reset). The other
/// accounts and the database key are not touched. Throws when the move fails:
/// everything is moved back and nothing is deleted.
Future<void> setAccountDatabaseAside(
  String clientName, {
  @visibleForTesting
  Future<String> Function(String clientName) databasePath = _getDatabasePath,
  @visibleForTesting Future<void> Function(File file, String newPath)? rename,
}) async {
  if (kIsWeb) return;
  final path = await databasePath(clientName);
  if (rename == null) return quarantineDatabase(path, maxCopies: null);
  await quarantineDatabase(path, rename: rename, maxCopies: null);
}

/// Quarantined copies of one account's database: they are encrypted with the
/// key that outlives a logout, so they go with the account.
Future<void> deleteQuarantinedCopiesOf(String clientName) async =>
    deleteQuarantinedDatabases(await _getDatabasePath(clientName));

Future<String> _getDatabaseDirectory() async {
  if (PlatformInfos.isIOS) {
    final containerPath = await PathProviderFoundation().getContainerPath(
      appGroupIdentifier: AppConfig.appleAppGroupId,
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
