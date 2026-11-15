// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/custom_reaction_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The quick reactions (DESIGN.md 5.3, turn 2 long-press): 38 px emoji
/// circles in a surface pill and a tile for the full picker. Reactions the
/// user already sent are dimmed and cannot be sent twice.
class ReactionBar extends StatelessWidget {
  final Room room;
  final Set<String> sentReactions;
  final void Function(String emoji) onReact;

  const ReactionBar({
    required this.room,
    required this.sentReactions,
    required this.onReact,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Material(
      color: tokens.surf,
      elevation: 0,
      borderRadius: BorderRadius.circular(AppRadius.reactionBar),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.reactionBar),
          boxShadow: AppElevation.reactionBar,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.xxs,
              children: [
                for (final emoji in AppConfig.defaultReactions)
                  Semantics(
                    button: true,
                    label: emoji,
                    enabled: !sentReactions.contains(emoji),
                    excludeSemantics: true,
                    onTap: sentReactions.contains(emoji)
                        ? null
                        : () => onReact(emoji),
                    child: InkResponse(
                      radius: AppChat.reactionBarEmoji / 2,
                      onTap: sentReactions.contains(emoji)
                          ? null
                          : () => onReact(emoji),
                      child: SizedBox.square(
                        dimension: AppChat.reactionBarEmoji + 6,
                        child: Center(
                          child: Opacity(
                            opacity: sentReactions.contains(emoji) ? 0.33 : 1,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.add_reaction_rounded),
                  tooltip: l10n.moreReactions,
                  onPressed: () async {
                    final emoji = await showCustomReactionSheet(context, room);
                    if (emoji == null || sentReactions.contains(emoji)) return;
                    onReact(emoji);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
