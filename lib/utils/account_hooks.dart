// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/show_update_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _processHooksDone = false;

/// Work that belongs to a logged in account, not to a tab: it must run once
/// per account whichever tab the app starts on.
Future<void> runAccountHooks(
  MatrixState matrix,
  Client client,
  BuildContext context,
) async {
  await matrix.backgroundPush?.setupPush(context);
  if (!context.mounted) return;
  if (!_processHooksDone) {
    _processHooksDone = true;
    UpdateNotifier.showUpdateDialog(context);
    UpdateNotifier.showUpdateAvailableBanner(context);
    processPushHelperCrashReport(context, matrix.store);
  }
  await showUnverifiedDeviceNoticeAfterFirstSync(client, context);
}

void processPushHelperCrashReport(
  BuildContext context,
  SharedPreferences store,
) {
  if (AppSettings.autoSendErrorReports.value != true) return;
  final report = store.getStringList(AppConfig.pushHelperCrashReportKey);
  if (report == null) return;
  store.remove(AppConfig.pushHelperCrashReportKey);
  ErrorReporter(
    context,
    'Push Helper has been crashed',
  ).onErrorCallback(report.first, StackTrace.fromString(report.last));
}

Future<void> showUnverifiedDeviceNoticeAfterFirstSync(
  Client client,
  BuildContext context,
) async {
  await client.roomsLoading;
  await client.accountDataLoading;
  await client.userDeviceKeysLoading;
  if (client.prevBatch == null) {
    await client.onSyncStatus.stream.firstWhere(
      (status) => status.status == SyncStatus.finished,
    );
  }
  if (!context.mounted) return;
  if (Matrix.of(context).activeClientOrNull != client) return;
  final hasUnverified =
      client.userDeviceKeys[client.userID]?.deviceKeys.values.any(
        (device) => !device.verified && !device.blocked,
      ) ??
      false;
  if (!hasUnverified) return;

  late final ScaffoldFeatureController controller;
  final theme = Theme.of(context);
  final l10n = L10n.of(context);
  controller = ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 15),
      showCloseIcon: true,
      backgroundColor: theme.colorScheme.errorContainer,
      closeIconColor: theme.colorScheme.onErrorContainer,
      content: Text(
        l10n.oneOfYourDevicesIsNotVerified,
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      ),
      action: SnackBarAction(
        onPressed: () {
          controller.close();
          FluffyChatApp.router.go('/settings/devices');
        },
        textColor: theme.colorScheme.onErrorContainer,
        label: l10n.settings,
      ),
    ),
  );
}
