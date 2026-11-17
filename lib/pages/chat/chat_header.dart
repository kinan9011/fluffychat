// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_overflow_menu.dart';
import 'package:fluffychat/utils/chat_list/swipe_actions.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:fluffychat/widgets/pulsating_widget.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum _EventContextAction { info, report }

/// Three separate glass shapes (DESIGN.md 5.2): back, title pill, overflow.
class ChatHeader extends StatefulWidget {
  final ChatController controller;

  const ChatHeader(this.controller, {super.key});

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader> {
  final _menuOpen = ValueNotifier(false);
  final _overflowKey = GlobalKey();

  ChatController get controller => widget.controller;
  Room get room => controller.room;

  @override
  void dispose() {
    _menuOpen.dispose();
    super.dispose();
  }

  Future<void> _openOverflow() async {
    final box = _overflowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final hasActiveCall = room.hasActiveMatrixRtcCall;
    final actions = chatOverflowActions(
      muted: room.pushRuleState != PushRuleState.notify,
      canCall:
          !hasActiveCall &&
          room.hasPermissionForMatrixRtcCall &&
          controller.supportLiveKitCalls,
      showDetails: true,
      joined: room.membership == Membership.join,
      left: room.membership == Membership.leave,
      canSchedule: room.canSendDefaultMessages,
    );
    _menuOpen.value = true;
    final action = await showChatOverflowMenu(
      context,
      actions: actions,
      anchor: anchor,
    );
    _menuOpen.value = false;
    if (action == null || !mounted) return;
    await _run(action);
  }

  Future<void> _run(ChatOverflowAction action) async {
    switch (action) {
      case ChatOverflowAction.mute:
      case ChatOverflowAction.unmute:
        await showFutureLoadingDialog(
          context: context,
          future: () => runSwipeAction(
            room.client,
            room.id,
            SwipeAction.mute,
            publicReceipts: AppSettings.sendPublicReadReceipts.value,
          ),
        );
      case ChatOverflowAction.videoCall:
        controller.startOrJoinVideoCall();
      case ChatOverflowAction.search:
        context.go('/rooms/${room.id}/search');
      case ChatOverflowAction.scheduled:
        context.go('/rooms/${room.id}/scheduled');
      case ChatOverflowAction.wallpaper:
        context.go('/settings/style');
      case ChatOverflowAction.details:
        final path = GoRouterState.of(context).uri.path;
        context.go(
          path.endsWith('/details')
              ? '/rooms/${room.id}'
              : '/rooms/${room.id}/details',
        );
      case ChatOverflowAction.encryption:
        context.go('/rooms/${room.id}/encryption');
      case ChatOverflowAction.leave:
        final l10n = L10n.of(context);
        final router = GoRouter.of(context);
        final confirmed = await showOkCancelAlertDialog(
          context: context,
          title: l10n.areYouSure,
          message: l10n.archiveRoomDescription,
          okLabel: l10n.leave,
          cancelLabel: l10n.cancel,
          isDestructive: true,
        );
        if (confirmed != OkCancelResult.ok) return;
        if (!mounted) return;
        final result = await showFutureLoadingDialog(
          context: context,
          future: room.leave,
        );
        if (result.error == null) router.go('/rooms');
    }
  }

  @override
  Widget build(BuildContext context) {
    final columnMode = FluffyThemes.isColumnMode(context);
    final threadId = controller.activeThreadId;
    final l10n = L10n.of(context);
    final Widget? leading = controller.selectMode
        ? _GlassCircle(
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l10n.close,
              onPressed: controller.clearSelectedEvents,
            ),
          )
        : threadId != null
        ? _GlassCircle(
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l10n.backToMainChat,
              onPressed: controller.closeThread,
            ),
          )
        : columnMode
        ? null
        : const _GlassCircle(child: BackButton());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Row(
        spacing: AppChat.headerGap,
        children: [
          ?leading,
          Expanded(
            child: controller.selectMode
                ? _SelectionPill(controller)
                : _TitlePill(controller),
          ),
          if (!controller.selectMode && !room.isArchived)
            ValueListenableBuilder(
              valueListenable: _menuOpen,
              builder: (context, open, _) => _GlassCircle(
                key: _overflowKey,
                tinted: open,
                child: IconButton(
                  key: const Key('chat_overflow_button'),
                  icon: const Icon(Icons.more_vert_rounded),
                  tooltip: l10n.moreOptions,
                  onPressed: _openOverflow,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  final Widget child;
  final bool tinted;

  const _GlassCircle({required this.child, this.tinted = false, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox.square(
      dimension: AppChat.headerButton,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppChat.headerButton / 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tinted ? tokens.accs : null,
          ),
          child: IconTheme(
            data: IconThemeData(
              size: 24,
              color: tinted ? tokens.acc : tokens.fg,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  final ChatController controller;

  const _TitlePill(this.controller);

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: AppChat.headerButton,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppChat.headerButton / 2),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 5, end: 14),
          child: Row(
            children: [
              Expanded(child: ChatAppBarTitle(controller)),
              if (room.hasActiveMatrixRtcCall && !room.isArchived)
                PulsatingWidget(
                  color: tokens.red,
                  child: TextButton.icon(
                    icon: Icon(switch (room.activeMatrixRtcCallIntent) {
                      .voice => Icons.video_call_outlined,
                      _ => Icons.mic_outlined,
                    }),
                    label: Text(
                      room.getActiveMatrixRtcMembers().length.toString(),
                    ),
                    onPressed: room.hasPermissionForMatrixRtcCall
                        ? controller.startOrJoinVideoCall
                        : null,
                    style: TextButton.styleFrom(
                      backgroundColor: tokens.red,
                      foregroundColor: tokens.onRed,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionPill extends StatelessWidget {
  final ChatController controller;

  const _SelectionPill(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: AppChat.headerButton,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppChat.headerButton / 2),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  controller.selectedEvents.length.toString(),
                  style: TextStyle(
                    color: tokens.fg,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (controller.canEditSelectedEvents)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.edit,
                  onPressed: controller.editSelectedEventAction,
                ),
              if (controller.selectedEvents.length == 1 &&
                  controller.activeThreadId == null &&
                  controller.room.canSendDefaultMessages)
                IconButton(
                  icon: const Icon(Icons.message_outlined),
                  tooltip: l10n.replyInThread,
                  onPressed: () => controller.enterThread(
                    controller.selectedEvents.single.eventId,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: l10n.copyToClipboard,
                onPressed: controller.copyEventsAction,
              ),
              if (controller.canRedactSelectedEvents)
                IconButton(
                  icon: const Icon(Icons.delete_outlined),
                  tooltip: l10n.deleteForEveryone,
                  onPressed: controller.redactEventsAction,
                ),
              if (controller.selectedEvents.length == 1)
                _SelectionMoreMenu(controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionMoreMenu extends StatelessWidget {
  final ChatController controller;

  const _SelectionMoreMenu(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return PopupMenuButton<_EventContextAction>(
      useRootNavigator: true,
      onSelected: (action) {
        switch (action) {
          case _EventContextAction.info:
            controller.showEventInfo();
            controller.clearSelectedEvents();
          case _EventContextAction.report:
            controller.reportEventAction();
        }
      },
      itemBuilder: (context) => [
        if (controller.canPinSelectedEvents)
          PopupMenuItem(
            onTap: controller.pinEvent,
            value: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.l,
              children: [
                const Icon(Icons.push_pin_outlined),
                Text(l10n.pinMessage),
              ],
            ),
          ),
        if (controller.canSaveSelectedEvent)
          PopupMenuItem(
            onTap: () => controller.saveSelectedEvent(context),
            value: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.l,
              children: [
                const Icon(Icons.download_outlined),
                Text(l10n.downloadFile),
              ],
            ),
          ),
        PopupMenuItem(
          value: _EventContextAction.info,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.l,
            children: [const Icon(Icons.info_outlined), Text(l10n.messageInfo)],
          ),
        ),
        if (controller.selectedEvents.single.status.isSent)
          PopupMenuItem(
            value: _EventContextAction.report,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.l,
              children: [
                Icon(Icons.shield_outlined, color: tokens.red),
                Text(l10n.reportMessage),
              ],
            ),
          ),
      ],
    );
  }
}
