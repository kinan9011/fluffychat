// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:material_ui/material_ui.dart';

/// What other people can see about this user: typing, read receipts and
/// online status. Every toggle is off until the user turns it on.
class PrivacyToggles extends StatelessWidget {
  const PrivacyToggles({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingsGroup(
      header: l10n.sectionVisibility,
      rows: [
        AppSettingToggleRow(
          icon: Icons.keyboard_rounded,
          title: l10n.sendTypingNotifications,
          subtitle: l10n.sendTypingNotificationsDescription,
          setting: AppSettings.sendTypingNotifications,
          defaultValue: AppSettings.sendTypingNotifications.defaultValue,
        ),
        AppSettingToggleRow(
          icon: Icons.done_all_rounded,
          title: l10n.sendReadReceipts,
          subtitle:
              '${l10n.sendReadReceiptsDescription} ${l10n.readReceiptsPrivateNote}',
          setting: AppSettings.sendPublicReadReceipts,
          defaultValue: AppSettings.sendPublicReadReceipts.defaultValue,
        ),
        AppSettingToggleRow(
          icon: Icons.circle_outlined,
          title: l10n.showOnlineStatus,
          subtitle: l10n.showOnlineStatusDescription,
          setting: AppSettings.shareOnlineStatus,
          defaultValue: AppSettings.shareOnlineStatus.defaultValue,
        ),
        AppSettingToggleRow(
          icon: Icons.visibility_off_rounded,
          title: l10n.appearOffline,
          subtitle: l10n.appearOfflineDescription,
          setting: AppSettings.appearOffline,
          defaultValue: AppSettings.appearOffline.defaultValue,
        ),
      ],
    );
  }
}
