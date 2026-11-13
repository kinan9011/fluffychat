// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

const _passwordStorageKey = 'database_password';

const iosOptions = IOSOptions(
  groupId: 'group.im.fluffychat.app',
  accessibility: .first_unlock,
);

bool _unencryptedThisSession = false;

/// Also true when persisting the flag failed, so the notice is never lost.
bool get isDatabaseUnencrypted =>
    _unencryptedThisSession || AppSettings.databaseUnencrypted.value;

typedef MarkDatabaseEncryption =
    Future<void> Function({required bool isEncrypted});

Future<String?> getDatabaseCipher({
  @visibleForTesting
  MarkDatabaseEncryption markEncryption = markDatabaseEncryption,
}) async {
  String? password;

  try {
    password = await FlutterSecureStorage(
      iOptions: iosOptions,
    ).read(key: _passwordStorageKey, iOptions: iosOptions);
    if (password != null) {
      await _markEncryption(markEncryption, isEncrypted: true);
      return password;
    }

    if (PlatformInfos.isIOS) {
      final legacyPassword = await FlutterSecureStorage().read(
        key: _passwordStorageKey,
      );
      if (legacyPassword != null) {
        Logs().i('Migrate database key location on iOS...');
        await FlutterSecureStorage().delete(key: _passwordStorageKey);
        await FlutterSecureStorage(iOptions: iosOptions).write(
          key: _passwordStorageKey,
          value: legacyPassword,
          iOptions: iosOptions,
        );
        await _markEncryption(markEncryption, isEncrypted: true);
        return legacyPassword;
      }
    }

    final rng = Random.secure();
    final list = Uint8List(32);
    list.setAll(0, Iterable.generate(list.length, (i) => rng.nextInt(256)));
    final newPassword = base64UrlEncode(list);
    await FlutterSecureStorage(
      iOptions: iosOptions,
    ).write(key: _passwordStorageKey, value: newPassword, iOptions: iosOptions);
    // workaround for if we just wrote to the key and it still doesn't exist
    password = await FlutterSecureStorage(
      iOptions: iosOptions,
    ).read(key: _passwordStorageKey, iOptions: iosOptions);
    if (password == null) throw MissingPluginException();
    await _markEncryption(markEncryption, isEncrypted: true);
    return password;
  } on MissingPluginException catch (e) {
    FlutterSecureStorage(
      iOptions: iosOptions,
    ).delete(key: _passwordStorageKey, iOptions: iosOptions).catchError((_) {});
    Logs().w('Database encryption is not supported on this platform', e);
    await _markEncryption(markEncryption, isEncrypted: false);
    _sendNoEncryptionWarning(e);
  } catch (e, s) {
    FlutterSecureStorage(
      iOptions: iosOptions,
    ).delete(key: _passwordStorageKey, iOptions: iosOptions).catchError((_) {});
    Logs().w('Unable to init database encryption', e, s);
    await _markEncryption(markEncryption, isEncrypted: false);
    _sendNoEncryptionWarning(e);
  }
  return null;
}

Future<void> markDatabaseEncryption({required bool isEncrypted}) async {
  if (isEncrypted) {
    if (AppSettings.databaseUnencrypted.value) {
      await AppSettings.databaseUnencrypted.setItem(false);
    }
    if (AppSettings.noEncryptionWarningShown.value) {
      await AppSettings.noEncryptionWarningShown.setItem(false);
    }
    if (AppSettings.databaseUnencryptedNoticeDismissed.value) {
      await AppSettings.databaseUnencryptedNoticeDismissed.setItem(false);
    }
    return;
  }
  if (AppSettings.databaseUnencrypted.value) return;
  await AppSettings.databaseUnencrypted.setItem(true);
  await AppSettings.databaseUnencryptedNoticeDismissed.setItem(false);
}

/// Bookkeeping for the UI must never throw into the key handling above: an
/// exception there would reach the catch blocks that delete the database key.
Future<void> _markEncryption(
  MarkDatabaseEncryption mark, {
  required bool isEncrypted,
}) async {
  _unencryptedThisSession = !isEncrypted;
  try {
    await mark(isEncrypted: isEncrypted);
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
