// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:material_ui/material_ui.dart';

enum ChatOverflowAction {
  mute,
  unmute,
  videoCall,
  search,
  wallpaper,
  details,
  encryption,
  leave,
}

/// Only entries that have a real action: no Scheduled messages (W06) and no
/// Clear history (Matrix cannot do it).
List<ChatOverflowAction> chatOverflowActions({
  required bool muted,
  required bool canCall,
  required bool showDetails,
  required bool joined,
  required bool left,
}) => [
  if (joined) muted ? ChatOverflowAction.unmute : ChatOverflowAction.mute,
  if (canCall) ChatOverflowAction.videoCall,
  if (joined || left) ChatOverflowAction.search,
  ChatOverflowAction.wallpaper,
  if (showDetails && joined) ChatOverflowAction.details,
  if (joined || left) ChatOverflowAction.encryption,
  ChatOverflowAction.leave,
];

({IconData icon, String label, bool destructive}) _entry(
  L10n l10n,
  ChatOverflowAction action,
) => switch (action) {
  ChatOverflowAction.mute => (
    icon: Icons.notifications_off_rounded,
    label: l10n.mute,
    destructive: false,
  ),
  ChatOverflowAction.unmute => (
    icon: Icons.notifications_rounded,
    label: l10n.unmute,
    destructive: false,
  ),
  ChatOverflowAction.videoCall => (
    icon: Icons.videocam_rounded,
    label: l10n.videoCall,
    destructive: false,
  ),
  ChatOverflowAction.search => (
    icon: Icons.search_rounded,
    label: l10n.search,
    destructive: false,
  ),
  ChatOverflowAction.wallpaper => (
    icon: Icons.wallpaper_rounded,
    label: l10n.changeWallpaper,
    destructive: false,
  ),
  ChatOverflowAction.details => (
    icon: Icons.info_outline_rounded,
    label: l10n.chatDetails,
    destructive: false,
  ),
  ChatOverflowAction.encryption => (
    icon: Icons.lock_outline_rounded,
    label: l10n.encryption,
    destructive: false,
  ),
  ChatOverflowAction.leave => (
    icon: Icons.logout_rounded,
    label: l10n.leaveChat,
    destructive: true,
  ),
};

/// Glass card right-aligned under the header, [anchor] is the overflow button.
Future<ChatOverflowAction?> showChatOverflowMenu(
  BuildContext context, {
  required List<ChatOverflowAction> actions,
  required Rect anchor,
}) => showGeneralDialog<ChatOverflowAction>(
  context: context,
  barrierDismissible: true,
  barrierLabel: L10n.of(context).close,
  barrierColor: AppTokens.overlay(0.18),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 120),
  pageBuilder: (dialogContext, _, _) {
    final l10n = L10n.of(dialogContext);
    final screen = MediaQuery.sizeOf(dialogContext);
    final safe = MediaQuery.paddingOf(dialogContext);
    final top = math.max(anchor.bottom + 8, safe.top + 8);
    final rtl = Directionality.of(dialogContext) == TextDirection.rtl;
    return Stack(
      children: [
        Positioned(
          top: top,
          left: rtl ? anchor.left : null,
          right: rtl ? null : screen.width - anchor.right,
          child: GlassMenuCard(
            maxHeight: math.max(0, screen.height - top - safe.bottom - 8),
            children: [
              for (final (i, action) in actions.indexed)
                GlassMenuRow(
                  autofocus: i == 0,
                  icon: _entry(l10n, action).icon,
                  label: _entry(l10n, action).label,
                  destructive: _entry(l10n, action).destructive,
                  onTap: () => Navigator.of(dialogContext).pop(action),
                ),
            ],
          ),
        ),
      ],
    );
  },
);
