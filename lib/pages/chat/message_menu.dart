// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/reaction_bar.dart';
import 'package:fluffychat/pages/chat/message_action_runner.dart';
import 'package:fluffychat/utils/chat/menu_placement.dart';
import 'package:fluffychat/utils/chat/message_actions.dart';
import 'package:fluffychat/utils/chat/reaction_summary.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

({IconData icon, String label}) _entry(
  L10n l10n,
  MessageAction action,
) => switch (action) {
  MessageAction.reply => (icon: Icons.reply_rounded, label: l10n.reply),
  MessageAction.replyInThread => (
    icon: Icons.forum_rounded,
    label: l10n.replyInThread,
  ),
  MessageAction.edit => (icon: Icons.edit_rounded, label: l10n.edit),
  MessageAction.copy => (
    icon: Icons.content_copy_rounded,
    label: l10n.copyToClipboard,
  ),
  MessageAction.saveFile => (
    icon: Icons.download_rounded,
    label: l10n.downloadFile,
  ),
  MessageAction.pin => (icon: Icons.push_pin_rounded, label: l10n.pinMessage),
  MessageAction.unpin => (icon: Icons.push_pin_outlined, label: l10n.unpin),
  MessageAction.forward => (icon: Icons.forward_rounded, label: l10n.forward),
  MessageAction.select => (
    icon: Icons.check_circle_outline_rounded,
    label: l10n.select,
  ),
  MessageAction.editHistory => (
    icon: Icons.history_rounded,
    label: l10n.editHistory,
  ),
  MessageAction.info => (
    icon: Icons.info_outline_rounded,
    label: l10n.messageInfo,
  ),
  MessageAction.report => (icon: Icons.flag_rounded, label: l10n.reportMessage),
  MessageAction.delete => (
    icon: Icons.delete_rounded,
    label: l10n.deleteForEveryone,
  ),
};

/// Long press (DESIGN.md 5.3): dimmed chat, reaction bar and a glass menu next
/// to the pressed bubble. Nothing is selected or sent until the user picks
/// something.
Future<void> showMessageMenu({
  required BuildContext context,
  required ChatController controller,
  required Event event,
  required Rect anchor,
  required bool outgoing,
  required Timeline timeline,
}) async {
  final actions = availableMessageActions(
    messageActionContext(controller, event),
  );
  final canReact = event.room.canSendDefaultMessages && event.status.isSent;
  final sent = summarizeReactions(
    event.aggregatedEvents(timeline, RelationshipTypes.reaction),
    event.room.client.userID,
  ).entries.where((entry) => entry.own).map((entry) => entry.key).toSet();
  final picked = await showGeneralDialog<Object>(
    context: context,
    barrierDismissible: true,
    barrierLabel: L10n.of(context).close,
    barrierColor: AppTokens.overlay(0.28),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, _) => _MessageMenu(
      anchor: anchor,
      outgoing: outgoing,
      actions: actions,
      room: event.room,
      sentReactions: sent,
      canReact: canReact,
    ),
  );
  if (picked is String) {
    await event.room.sendReaction(event.eventId, picked);
    return;
  }
  if (picked is! MessageAction) return;
  await runMessageAction(controller, picked, event);
}

class _MessageMenu extends StatelessWidget {
  final Rect anchor;
  final bool outgoing;
  final List<MessageAction> actions;
  final Room room;
  final Set<String> sentReactions;
  final bool canReact;

  const _MessageMenu({
    required this.anchor,
    required this.outgoing,
    required this.actions,
    required this.room,
    required this.sentReactions,
    required this.canReact,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final barSize = canReact
        ? Size(
            AppConfig.defaultReactions.length *
                    (AppChat.reactionBarEmoji + 10) +
                64,
            AppChat.reactionBarEmoji + 20,
          )
        : Size.zero;
    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final available =
        screen.height -
        safe.vertical -
        2 * AppChat.menuGap -
        (canReact ? barSize.height + AppChat.menuGap : 0);
    final menuSize = Size(
      AppChat.menuWidth,
      math.min(
        menuHeightFor(actions.length, MediaQuery.textScalerOf(context)),
        math.max(0, available),
      ),
    );
    final placement = placeMessageMenu(
      anchor: anchor,
      screen: screen,
      safe: safe,
      barSize: barSize,
      menuSize: menuSize,
      outgoing: outgoing,
      direction: Directionality.of(context),
    );
    return Stack(
      children: [
        if (canReact)
          Positioned(
            left: placement.barTopLeft.dx,
            top: placement.barTopLeft.dy,
            child: ReactionBar(
              room: room,
              sentReactions: sentReactions,
              onReact: (emoji) => Navigator.of(context).pop(emoji),
            ),
          ),
        Positioned(
          left: placement.menuTopLeft.dx,
          top: placement.menuTopLeft.dy,
          child: GlassMenuCard(
            maxHeight: menuSize.height,
            children: [
              for (final (i, action) in actions.indexed)
                GlassMenuRow(
                  autofocus: i == 0,
                  icon: _entry(l10n, action).icon,
                  label: _entry(l10n, action).label,
                  destructive: action == MessageAction.delete,
                  onTap: () => Navigator.of(context).pop(action),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
