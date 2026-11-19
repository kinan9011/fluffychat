// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat_list/peek_sheet.dart';
import 'package:odango/utils/chat_list/peek_menu.dart';
import 'package:odango/utils/chat_list/swipe_actions.dart';
import 'package:odango/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:odango/widgets/future_loading_dialog.dart';
import 'package:odango/widgets/matrix.dart';

class ChatRowActions {
  final Future<void> Function(String roomId, SwipeAction action) run;
  final void Function(String roomId, BuildContext context) more;
  final void Function(String roomId, BuildContext context) peek;
  final ValueNotifier<String?> openRow;

  const ChatRowActions({
    required this.run,
    required this.more,
    required this.peek,
    required this.openRow,
  });

  factory ChatRowActions.forChatList(
    BuildContext context,
    ValueNotifier<String?> openRow,
    void Function(Room room, BuildContext rowContext) more,
    void Function(Room room) leave,
  ) => ChatRowActions(
    openRow: openRow,
    run: (roomId, action) =>
        _runRowAction(context, Matrix.of(context).client, roomId, action),
    more: (roomId, rowContext) {
      final room = Matrix.of(context).client.getRoomById(roomId);
      if (room != null && rowContext.mounted) more(room, rowContext);
    },
    peek: (roomId, rowContext) {
      final room = Matrix.of(context).client.getRoomById(roomId);
      if (room == null || !room.canSwipe) return;
      showPeek(
        rowContext,
        room,
        onOpenChat: () {
          if (context.mounted) context.go('/rooms/${room.id}');
        },
        onSelect: (item, shown) {
          if (!context.mounted || !peekStillShown(room, item, shown)) return;
          switch (item) {
            case PeekMenuItem.toggleRead:
              _runRowAction(
                context,
                room.client,
                room.id,
                SwipeAction.toggleRead,
              );
            case PeekMenuItem.pin:
              _runRowAction(context, room.client, room.id, SwipeAction.pin);
            case PeekMenuItem.mute:
              _runRowAction(context, room.client, room.id, SwipeAction.mute);
            case PeekMenuItem.archive:
              _runRowAction(context, room.client, room.id, SwipeAction.archive);
            case PeekMenuItem.leave:
              leave(room);
            case PeekMenuItem.more:
              if (rowContext.mounted) more(room, rowContext);
          }
        },
      );
    },
  );
}

Future<void> _runRowAction(
  BuildContext context,
  Client client,
  String roomId,
  SwipeAction action,
) async {
  await showFutureLoadingDialog(
    context: context,
    future: () => runSwipeAction(
      client,
      roomId,
      action,
      publicReceipts: AppSettings.sendPublicReadReceipts.value,
    ),
  );
}

class SwipeActionRow extends StatefulWidget {
  static const buttonWidth = 72.0;
  static const trayWidth = buttonWidth * 3;
  static const _supportedDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };

  final String roomId;
  final ChatRowActions actions;
  final bool unread;
  final bool muted;
  final bool pinned;
  final bool archived;
  final Widget child;

  const SwipeActionRow({
    required this.roomId,
    required this.actions,
    required this.unread,
    required this.muted,
    required this.pinned,
    required this.archived,
    required this.child,
    super.key,
  });

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow>
    with SingleTickerProviderStateMixin {
  static const _openThreshold = SwipeActionRow.trayWidth / 2;
  static const _readThreshold = SwipeActionRow.buttonWidth * 0.78;

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  var _dragged = false;

  double get _offset => _controller.value;

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    widget.actions.openRow.addListener(_onOpenRowChanged);
  }

  @override
  void didUpdateWidget(SwipeActionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actions.openRow != widget.actions.openRow) {
      oldWidget.actions.openRow.removeListener(_onOpenRowChanged);
      widget.actions.openRow.addListener(_onOpenRowChanged);
    }
    if (oldWidget.roomId != widget.roomId) _controller.value = 0;
  }

  @override
  void dispose() {
    widget.actions.openRow.removeListener(_onOpenRowChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onOpenRowChanged() {
    final open = widget.actions.openRow.value;
    if (open != widget.roomId && _offset != 0) _animateTo(0);
  }

  void _animateTo(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
      return;
    }
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _close() => _animateTo(0);

  void _update(DragUpdateDetails details) {
    _dragged = true;
    final logical = details.delta.dx * (_rtl ? -1 : 1);
    _controller.value = (_offset + logical).clamp(
      -SwipeActionRow.trayWidth,
      SwipeActionRow.buttonWidth,
    );
  }

  void _end(DragEndDetails details) {
    if (!_dragged) return;
    _dragged = false;
    if (_offset <= -_openThreshold) {
      widget.actions.openRow.value = widget.roomId;
      _animateTo(-SwipeActionRow.trayWidth);
      return;
    }
    if (_offset >= _readThreshold) {
      widget.actions.run(widget.roomId, SwipeAction.toggleRead);
    }
    _animateTo(0);
  }

  void _run(SwipeAction action) {
    widget.actions.run(widget.roomId, action);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final sign = _rtl ? -1.0 : 1.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: SwipeActionRow._supportedDevices,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _dragged = false,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Stack(
            children: [
              if (_offset > 0)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: SwipeActionRow.buttonWidth,
                  child: ExcludeSemantics(
                    child: _TrayButton(
                      key: const ValueKey('swipe_toggle_read'),
                      color: tokens.acc,
                      foreground: tokens.onacc,
                      icon: widget.unread
                          ? Icons.mark_chat_read_rounded
                          : Icons.mark_chat_unread_rounded,
                      label: widget.unread
                          ? l10n.markAsRead
                          : l10n.markAsUnread,
                      onTap: () => _run(SwipeAction.toggleRead),
                    ),
                  ),
                ),
              if (_offset < 0)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  width: SwipeActionRow.trayWidth,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        _TrayButton(
                          key: const ValueKey('swipe_mute'),
                          color: tokens.mbad,
                          foreground: Colors.white,
                          icon: Icons.notifications_off_rounded,
                          label: widget.muted ? l10n.unmute : l10n.mute,
                          onTap: () => _run(SwipeAction.mute),
                        ),
                        _TrayButton(
                          key: const ValueKey('swipe_pin'),
                          color: tokens.okS,
                          foreground: tokens.onOkS,
                          icon: Icons.push_pin_rounded,
                          label: widget.pinned ? l10n.unpin : l10n.pin,
                          onTap: () => _run(SwipeAction.pin),
                        ),
                        _TrayButton(
                          key: const ValueKey('swipe_archive'),
                          color: tokens.acc,
                          foreground: tokens.onacc,
                          icon: Icons.inventory_2_rounded,
                          label: widget.archived
                              ? l10n.unarchive
                              : l10n.archive,
                          onTap: () => _run(SwipeAction.archive),
                        ),
                      ],
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(_offset * sign, 0),
                child: _offset == 0
                    ? child
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                        child: AbsorbPointer(child: child),
                      ),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _TrayButton extends StatelessWidget {
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TrayButton({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: SwipeActionRow.buttonWidth,
    child: Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 3,
          children: [
            Icon(icon, size: 22, color: foreground),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
