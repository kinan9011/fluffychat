// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).chat),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: Column(
            children: [
              const _SpaceNavigationSection(),
              ListTile(
                key: const ValueKey('settings_folders'),
                leading: const Icon(Icons.folder_outlined),
                title: Text(L10n.of(context).folders),
                onTap: () => context.go('/settings/chat/folders'),
                trailing: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Icon(Icons.chevron_right_outlined),
                ),
              ),
              const Divider(),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).formattedMessages,
                subtitle: L10n.of(context).formattedMessagesDescription,
                setting: AppSettings.renderHtml,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRedactedMessages,
                subtitle: L10n.of(context).hideRedactedMessagesBody,
                setting: AppSettings.hideRedactedEvents,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRoomsInSpaces,
                setting: AppSettings.hideRoomsInSpaces,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideInvalidOrUnknownMessageFormats,
                setting: AppSettings.hideUnknownEvents,
              ),
              if (PlatformInfos.isMobile)
                SettingsSwitchListTile.adaptive(
                  title: L10n.of(context).autoplayImages,
                  setting: AppSettings.autoplayImages,
                ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).sendOnEnter,
                setting: AppSettings.sendOnEnter,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).swipeRightToLeftToReply,
                setting: AppSettings.swipeRightToLeftToReply,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).showThumbnailsInTimeline,
                setting: AppSettings.showThumbnailsInTimeline,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).doubleTapToReact,
                subtitle: L10n.of(context).doubleTapToReactDescription,
                setting: AppSettings.doubleTapToReact,
                onChanged: (_) => controller.updateState(),
              ),
              if (AppSettings.doubleTapToReact.value)
                ListTile(
                  title: Text(L10n.of(context).doubleTapReaction),
                  trailing: Text(
                    AppSettings.doubleTapReaction.value,
                    style: const TextStyle(fontSize: 24),
                  ),
                  onTap: () async {
                    final emoji = await showAdaptiveBottomSheet<String>(
                      context: context,
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: Text(L10n.of(context).doubleTapReaction),
                          leading: CloseButton(
                            onPressed: () => Navigator.of(context).pop(null),
                          ),
                        ),
                        body: SizedBox(
                          height: double.infinity,
                          child: EmojiPicker(
                            onEmojiSelected: (_, emoji) =>
                                Navigator.of(context).pop(emoji.emoji),
                            config: Config(
                              locale: Localizations.localeOf(context),
                              emojiViewConfig: const EmojiViewConfig(
                                backgroundColor: Colors.transparent,
                              ),
                              bottomActionBarConfig:
                                  const BottomActionBarConfig(enabled: false),
                              categoryViewConfig: CategoryViewConfig(
                                initCategory: Category.SMILEYS,
                                backspaceColor: theme.colorScheme.primary,
                                iconColor: theme.colorScheme.primary.withAlpha(
                                  128,
                                ),
                                iconColorSelected: theme.colorScheme.primary,
                                indicatorColor: theme.colorScheme.primary,
                                backgroundColor: theme.colorScheme.surface,
                              ),
                              skinToneConfig: SkinToneConfig(
                                dialogBackgroundColor: Color.lerp(
                                  theme.colorScheme.surface,
                                  theme.colorScheme.primaryContainer,
                                  0.75,
                                )!,
                                indicatorColor: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    if (emoji != null) {
                      await AppSettings.doubleTapReaction.setItem(emoji);
                      controller.updateState();
                    }
                  },
                ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).customEmojisAndStickers,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                title: Text(L10n.of(context).customEmojisAndStickers),
                subtitle: Text(L10n.of(context).customEmojisAndStickersBody),
                onTap: () => context.go('/settings/chat/emotes'),
                trailing: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Icon(Icons.chevron_right_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpaceNavigationSection extends StatelessWidget {
  const _SpaceNavigationSection();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(
            l10n.spaceNavigation,
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: AppSettings.spaceNavigation.listenable,
          builder: (context, _, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<SpaceNavigationMode>(
              selected: {
                SpaceNavigationMode.fromSetting(
                  AppSettings.spaceNavigation.value,
                ),
              },
              onSelectionChanged: (selected) =>
                  AppSettings.spaceNavigation.setItem(selected.single.name),
              segments: [
                ButtonSegment(
                  value: SpaceNavigationMode.tabs,
                  label: Text(l10n.spaceNavigationTabs),
                ),
                ButtonSegment(
                  value: SpaceNavigationMode.switcher,
                  label: Text(l10n.spaceNavigationSwitcher),
                ),
              ],
            ),
          ),
        ),
        SettingsSwitchListTile.adaptive(
          title: l10n.showFoldersAfterSpaces,
          setting: AppSettings.showFoldersAfterSpaces,
        ),
        SettingsSwitchListTile.adaptive(
          title: l10n.showUnreadCountsOnTabs,
          setting: AppSettings.showTabUnreadCounts,
        ),
        SettingsSwitchListTile.adaptive(
          title: l10n.unarchiveOnMention,
          subtitle: l10n.unarchiveOnMentionDescription,
          setting: AppSettings.unarchiveOnMention,
        ),
      ],
    );
  }
}
