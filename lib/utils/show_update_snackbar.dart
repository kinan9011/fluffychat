// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/support/support_dialog.dart';
import 'package:odango/utils/branding/repo_links.dart';
import 'package:odango/utils/launch_web_url.dart';
import 'package:odango/utils/platform_infos.dart';
import 'package:odango/utils/update_checker.dart';
import 'package:odango/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class UpdateNotifier {
  static const String versionStoreKey = 'last_known_version';
  static const String dismissedUpdateStoreKey = 'dismissed_update_version';

  /// Checks GitHub for a newer release with a Windows installer and
  /// displays a banner with a download link. Only for Windows, as all other
  /// platforms get updated by their store or package manager.
  static Future<void> showUpdateAvailableBanner(BuildContext context) async {
    if (!PlatformInfos.isWindows || !AppSettings.checkForUpdates.value) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);

    // Check for updates at most once per day
    final today = DateTime.now().toIso8601String().split('T').first;
    if (AppSettings.lastUpdateCheckDate.value == today) return;
    await AppSettings.lastUpdateCheckDate.setItem(today);

    final client = http.Client();
    final update = await checkForUpdate(
      client: client,
      repo: RepoLinks.confirmed(),
      currentVersion: await PlatformInfos.getVersion(),
    );
    client.close();
    if (update == null) return;
    final latestVersion = update.version;
    final downloadUrl = update.downloadUrl;

    final store = await SharedPreferences.getInstance();
    if (store.getString(dismissedUpdateStoreKey) == latestVersion) return;

    scaffoldMessenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update_outlined),
        content: Text(l10n.updateAvailable(latestVersion)),
        actions: [
          TextButton(
            onPressed: () {
              store.setString(dismissedUpdateStoreKey, latestVersion);
              scaffoldMessenger.hideCurrentMaterialBanner();
            },
            child: Text(l10n.close),
          ),
          TextButton(
            onPressed: () {
              launchWebUrl(downloadUrl);
              scaffoldMessenger.hideCurrentMaterialBanner();
            },
            child: Text(l10n.download),
          ),
        ],
      ),
    );
  }

  static Future<void> showUpdateDialog(BuildContext context) async {
    final l10n = L10n.of(context);
    final currentVersion = await PlatformInfos.getVersion();
    final store = await SharedPreferences.getInstance();
    final storedVersion = store.getString(versionStoreKey);
    if (!context.mounted) return;

    if (currentVersion != storedVersion) {
      if (storedVersion != null) {
        showDialog(
          barrierDismissible: true,
          context: context,
          builder: (context) => AlertDialog(
            title: Center(
              child: ClipOval(
                child: Image.asset(
                  'assets/logo/mini/logo_mini.png',
                  width: 96,
                  height: 96,
                ),
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 256),
              child: Column(
                mainAxisSize: .min,
                spacing: 16,
                children: [
                  Text(
                    l10n.updateInstalled(currentVersion),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    l10n.possibleByYou,
                    textAlign: .center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            actions: [
              AdaptiveDialogAction(
                bigButtons: true,
                targetPlatform: TargetPlatform.android,
                onPressed: () => showSupportDialog(context),
                child: Row(
                  mainAxisSize: .min,
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.favorite,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    Text(
                      l10n.support,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              AdaptiveDialogAction(
                bigButtons: true,
                targetPlatform: TargetPlatform.android,
                onPressed: () =>
                    launchWebUrl(RepoLinks.configured.releases.toString()),
                child: Text(l10n.changelog),
              ),
              AdaptiveDialogAction(
                bigButtons: true,
                targetPlatform: TargetPlatform.android,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.close),
              ),
            ],
          ),
        );
      }
      await store.setString(versionStoreKey, currentVersion);
    }
  }
}
