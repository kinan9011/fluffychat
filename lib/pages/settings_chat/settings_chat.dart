// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_chat_view.dart';

class SettingsChat extends StatefulWidget {
  const SettingsChat({super.key});

  @override
  SettingsChatController createState() => SettingsChatController();
}

class SettingsChatController extends State<SettingsChat> {
  Future<void> pickDoubleTapReaction() async {
    final theme = Theme.of(context);
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
              bottomActionBarConfig: const BottomActionBarConfig(
                enabled: false,
              ),
              categoryViewConfig: CategoryViewConfig(
                initCategory: Category.SMILEYS,
                backspaceColor: theme.colorScheme.primary,
                iconColor: theme.colorScheme.primary.withAlpha(128),
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
    if (emoji == null) return;
    await AppSettings.doubleTapReaction.setItem(emoji);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsChatView(this);
}
