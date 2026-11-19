// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/widgets/glass_surface.dart';

/// Stacked glass circles above the composer (DESIGN.md 5.2): jump to the next
/// unread mention and scroll to the bottom, each with a count badge.
class ChatJumpButtons extends StatelessWidget {
  @visibleForTesting
  static const mentionKey = ValueKey('jump_to_mention_button');
  @visibleForTesting
  static const scrollDownKey = ValueKey('scroll_to_bottom_button');

  final int mentionCount;
  final int unreadCount;
  final bool showScrollDown;
  final VoidCallback onMention;
  final VoidCallback onScrollDown;

  const ChatJumpButtons({
    required this.mentionCount,
    required this.unreadCount,
    required this.showScrollDown,
    required this.onMention,
    required this.onScrollDown,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: AppSpacing.m,
      children: [
        if (mentionCount > 0)
          _JumpButton(
            key: mentionKey,
            icon: Icons.alternate_email_rounded,
            iconColor: tokens.acc,
            count: mentionCount,
            label: l10n.jumpToMentionCount(mentionCount),
            onTap: onMention,
          ),
        if (showScrollDown)
          _JumpButton(
            key: scrollDownKey,
            icon: Icons.keyboard_arrow_down_rounded,
            iconColor: tokens.fg,
            count: unreadCount,
            label: unreadCount > 0
                ? l10n.scrollToBottomCount(unreadCount)
                : l10n.scrollToBottom,
            onTap: onScrollDown,
          ),
      ],
    );
  }
}

class _JumpButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final int count;
  final String label;
  final VoidCallback onTap;

  const _JumpButton({
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: AppChat.jumpHit,
          child: Center(
            child: SizedBox.square(
              dimension: AppChat.jumpButton,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GlassSurface(
                      borderRadius: BorderRadius.circular(
                        AppChat.jumpButton / 2,
                      ),
                      child: Center(
                        child: Icon(icon, size: 24, color: iconColor),
                      ),
                    ),
                  ),
                  if (count > 0)
                    PositionedDirectional(
                      top: -5,
                      end: -3,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: AppChat.jumpBadge,
                        ),
                        height: AppChat.jumpBadge,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.acc,
                          borderRadius: BorderRadius.circular(
                            AppChat.jumpBadge / 2,
                          ),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: TextStyle(
                            color: tokens.onacc,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
