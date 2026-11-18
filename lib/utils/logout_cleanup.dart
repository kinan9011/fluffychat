// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/app_temp_directory.dart';
import 'package:fluffychat/utils/draft_migration.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What an account leaves on the device besides the database the SDK clears at
/// logout: quarantined database copies (they open with the key that survives),
/// decrypted media in the app temp directory, the status timer (it holds the
/// Matrix ID), legacy plaintext drafts and the
/// notifications that show message previews. The recovery key the user chose
/// to remember on this device stays, as upstream does (W13-SECURITY C-4).
/// Every step is attempted; none of them throws.
class LogoutCleanup {
  const LogoutCleanup({
    required this.deleteQuarantined,
    required this.cancelNotifications,
    required this.deleteTempFiles,
    required this.prefs,
    required this.status,
  });

  /// The notification plugin replaces any platform instance a test installs,
  /// so a test that wants to see the call swaps the whole function.
  @visibleForTesting
  static Future<void> Function() cancelAllNotifications = () =>
      FlutterLocalNotificationsPlugin().cancelAll();

  factory LogoutCleanup.standard() {
    return LogoutCleanup(
      deleteQuarantined: deleteQuarantinedCopiesOf,
      cancelNotifications: () => cancelAllNotifications(),
      deleteTempFiles: deleteAppTempDirectory,
      prefs: AppSettings.store,
      status: StatusClearStore(),
    );
  }

  final Future<void> Function(String clientName) deleteQuarantined;
  final Future<void> Function() cancelNotifications;
  final Future<void> Function() deleteTempFiles;
  final SharedPreferences prefs;
  final StatusClearStore status;

  Future<void> run({
    required String clientName,
    required String? userId,
    required bool lastAccount,
  }) async {
    if (userId != null) {
      await _attempt('status timer', () => status.disarm(userId));
    }
    await _attempt('quarantined copies', () async {
      await deleteQuarantined(clientName);
      await AppSettings.databaseQuarantinedClients.setItem([
        for (final name in AppSettings.databaseQuarantinedClients.value)
          if (name != clientName) name,
      ]);
    });
    await _attempt('temp files', deleteTempFiles);
    if (!lastAccount) return;
    await _attempt('legacy drafts', () async {
      final keys = prefs.getKeys().where(
        (key) => key.startsWith(legacyDraftKeyPrefix),
      );
      for (final key in keys.toList()) {
        await prefs.remove(key);
      }
    });
    await _attempt('notifications', cancelNotifications);
  }

  Future<void> _attempt(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      Logs().w('Logout cleanup step failed: $what', e.runtimeType);
    }
  }
}
