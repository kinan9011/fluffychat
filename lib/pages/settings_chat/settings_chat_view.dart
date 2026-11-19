// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:fluffychat/widgets/settings/settings_segmented.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ValueListenableBuilder(
      valueListenable: AppSettings.doubleTapToReact.listenable,
      builder: (context, _, _) => SettingsScaffold(
        title: l10n.chat,
        children: [
          SettingsGroup(
            header: l10n.chatSettingsSectionChatList,
            footer: l10n.chatSettingsFooterChatList,
            rows: [
              const _SpaceNavigationRow(),
              SettingsRow(
                key: const ValueKey('settings_folders'),
                icon: Icons.folder_outlined,
                title: l10n.folders,
                onTap: () => context.go('/settings/chat/folders'),
              ),
              AppSettingToggleRow(
                icon: Icons.folder_special_outlined,
                title: l10n.showFoldersAfterSpaces,
                setting: AppSettings.showFoldersAfterSpaces,
              ),
              AppSettingToggleRow(
                icon: Icons.mark_chat_unread_outlined,
                title: l10n.showUnreadCountsOnTabs,
                setting: AppSettings.showTabUnreadCounts,
              ),
              AppSettingToggleRow(
                icon: Icons.visibility_off_outlined,
                title: l10n.hideRoomsInSpaces,
                setting: AppSettings.hideRoomsInSpaces,
              ),
              AppSettingToggleRow(
                icon: Icons.unarchive_outlined,
                title: l10n.unarchiveOnMention,
                subtitle: l10n.unarchiveOnMentionDescription,
                setting: AppSettings.unarchiveOnMention,
              ),
            ],
          ),
          SettingsGroup(
            header: l10n.chatSettingsSectionMessages,
            footer: l10n.chatSettingsFooterMessages,
            rows: [
              AppSettingToggleRow(
                icon: Icons.format_bold_rounded,
                title: l10n.formattedMessages,
                subtitle: l10n.formattedMessagesDescription,
                setting: AppSettings.renderHtml,
              ),
              AppSettingToggleRow(
                icon: Icons.delete_sweep_outlined,
                title: l10n.hideRedactedMessages,
                subtitle: l10n.hideRedactedMessagesBody,
                setting: AppSettings.hideRedactedEvents,
              ),
              AppSettingToggleRow(
                icon: Icons.report_gmailerrorred_rounded,
                title: l10n.hideInvalidOrUnknownMessageFormats,
                setting: AppSettings.hideUnknownEvents,
              ),
              AppSettingToggleRow(
                icon: Icons.image_outlined,
                title: l10n.showThumbnailsInTimeline,
                setting: AppSettings.showThumbnailsInTimeline,
              ),
              if (PlatformInfos.isMobile)
                AppSettingToggleRow(
                  icon: Icons.animation_rounded,
                  title: l10n.autoplayImages,
                  setting: AppSettings.autoplayImages,
                ),
            ],
          ),
          SettingsGroup(
            header: l10n.chatSettingsSectionWriting,
            footer: l10n.chatSettingsFooterWriting,
            rows: [
              AppSettingToggleRow(
                icon: Icons.keyboard_return_rounded,
                title: l10n.sendOnEnter,
                setting: AppSettings.sendOnEnter,
              ),
              AppSettingToggleRow(
                icon: Icons.swipe_left_rounded,
                title: l10n.swipeRightToLeftToReply,
                setting: AppSettings.swipeRightToLeftToReply,
              ),
              AppSettingToggleRow(
                icon: Icons.touch_app_outlined,
                title: l10n.doubleTapToReact,
                subtitle: l10n.doubleTapToReactDescription,
                setting: AppSettings.doubleTapToReact,
              ),
              if (AppSettings.doubleTapToReact.value)
                SettingsRow(
                  key: const ValueKey('settings_double_tap_reaction'),
                  icon: Icons.add_reaction_outlined,
                  title: l10n.doubleTapReaction,
                  value: AppSettings.doubleTapReaction.value,
                  onTap: controller.pickDoubleTapReaction,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpaceNavigationRow extends StatelessWidget {
  const _SpaceNavigationRow();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, top: 12, end: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: AppSpacing.l,
            children: [
              const SettingsIconTile(Icons.dashboard_customize_outlined),
              Expanded(
                child: Text(
                  l10n.spaceNavigation,
                  style: TextStyle(
                    color: tokens.fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: AppSettings.spaceNavigation.listenable,
            builder: (context, _, _) => SettingsSegmented<SpaceNavigationMode>(
              items: [
                (SpaceNavigationMode.tabs, l10n.spaceNavigationTabs),
                (SpaceNavigationMode.switcher, l10n.spaceNavigationSwitcher),
              ],
              value: SpaceNavigationMode.fromSetting(
                AppSettings.spaceNavigation.value,
              ),
              onChanged: (mode) =>
                  AppSettings.spaceNavigation.setItem(mode.name),
            ),
          ),
        ],
      ),
    );
  }
}
