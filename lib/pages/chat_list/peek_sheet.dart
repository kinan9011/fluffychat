// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat_list/peek_controller.dart';
import 'package:fluffychat/utils/chat_list/peek_menu.dart';
import 'package:fluffychat/utils/glass_policy.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

Future<void> showPeek(
  BuildContext context,
  Room room, {
  required void Function(PeekMenuItem item, bool shown) onSelect,
  required VoidCallback onOpenChat,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: L10n.of(context).close,
  barrierColor: Colors.transparent,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 150),
  pageBuilder: (dialogContext, _, _) => _PeekSheet(
    room: room,
    onOpenChat: () {
      Navigator.of(dialogContext).pop();
      onOpenChat();
    },
    onSelect: (item, shown) {
      Navigator.of(dialogContext).pop();
      onSelect(item, shown);
    },
  ),
);

class _PeekSheet extends StatefulWidget {
  final Room room;
  final VoidCallback onOpenChat;
  final void Function(PeekMenuItem item, bool shown) onSelect;

  const _PeekSheet({
    required this.room,
    required this.onOpenChat,
    required this.onSelect,
  });

  @override
  State<_PeekSheet> createState() => _PeekSheetState();
}

class _PeekSheetState extends State<_PeekSheet> {
  late final PeekController _controller = PeekController(widget.room);

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _controller.open();
    } catch (_) {
      Logs().w('[Peek] could not read the timeline');
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final mq = MediaQuery.of(context);
    final solid = glassIsSolidNow(context);
    final name = widget.room.getLocalizedDisplayname(MatrixLocals(l10n));
    final scrim = ColoredBox(
      color: AppTokens.overlay(0.32),
      child: const SizedBox.expand(),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: l10n.peek,
      explicitChildNodes: true,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: solid
                    ? scrim
                    : BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: scrim,
                      ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _PeekCard(
                          room: widget.room,
                          name: name,
                          controller: _controller,
                          onOpenChat: widget.onOpenChat,
                          bodyHeight: math.min(270, mq.size.height * 0.4),
                        ),
                      ),
                      _PeekMenu(
                        room: widget.room,
                        solid: mq.highContrast,
                        onSelect: widget.onSelect,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeekCard extends StatelessWidget {
  final Room room;
  final String name;
  final PeekController controller;
  final VoidCallback onOpenChat;
  final double bodyHeight;

  const _PeekCard({
    required this.room,
    required this.name,
    required this.controller,
    required this.onOpenChat,
    required this.bodyHeight,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surf,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.3),
            offset: Offset(0, 20),
            blurRadius: 50,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: onOpenChat,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: onOpenChat,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      spacing: 10,
                      children: [
                        Avatar(
                          client: room.client,
                          mxContent: room.avatar,
                          name: name,
                          colorSeed: room.id,
                          size: 40,
                        ),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.fg,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: tokens.line),
                SizedBox(
                  height: bodyHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: tokens.wallG),
                    child: ValueListenableBuilder<List<Event>>(
                      valueListenable: controller.events,
                      builder: (context, events, _) => events.isEmpty
                          ? Center(
                              child: Text(
                                l10n.noMessagesYet,
                                style: TextStyle(
                                  color: tokens.mut,
                                  fontSize: 14.5,
                                ),
                              ),
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(10),
                              itemCount: events.length,
                              itemBuilder: (context, i) =>
                                  _Bubble(room: room, event: events[i]),
                            ),
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: tokens.line),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        Icons.visibility_off_rounded,
                        size: 17,
                        color: tokens.mut,
                      ),
                      Expanded(
                        child: Text(
                          l10n.peekNotice(name),
                          style: TextStyle(
                            color: tokens.mut,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Room room;
  final Event event;

  const _Bubble({required this.room, required this.event});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final outgoing = event.senderId == room.client.userID;
    final text = event.calcLocalizedBodyFallback(
      MatrixLocals(l10n),
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
    );
    final showSender = !outgoing && !room.isDirectChat;
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: outgoing ? tokens.outS : tokens.surf,
        borderRadius: outgoing
            ? const BorderRadiusDirectional.only(
                topStart: Radius.circular(18),
                topEnd: Radius.circular(18),
                bottomStart: Radius.circular(18),
                bottomEnd: Radius.circular(6),
              )
            : const BorderRadiusDirectional.only(
                topStart: Radius.circular(18),
                topEnd: Radius.circular(18),
                bottomStart: Radius.circular(6),
                bottomEnd: Radius.circular(18),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: TextStyle(
            color: outgoing ? tokens.outFg : tokens.fg,
            fontSize: 14.5,
            height: 1.35,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 5),
      child: Align(
        alignment: outgoing
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 12,
                    bottom: 2,
                  ),
                  child: Text(
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: event.senderId.nameColor(
                        Theme.brightnessOf(context),
                      ),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              bubble,
            ],
          ),
        ),
      ),
    );
  }
}

class _PeekMenu extends StatelessWidget {
  final Room room;
  final bool solid;
  final void Function(PeekMenuItem item, bool shown) onSelect;

  const _PeekMenu({
    required this.room,
    required this.solid,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<SyncUpdate>(
    stream: room.client.onSync.stream.where((update) => update.hasRoomUpdate),
    builder: (context, _) {
      final tokens = AppTokens.of(context);
      final l10n = L10n.of(context);
      final muted = room.pushRuleState != PushRuleState.notify;
      final entries = [
        (
          PeekMenuItem.toggleRead,
          room.isUnread ? l10n.markAsRead : l10n.markAsUnread,
          room.isUnread
              ? Icons.mark_chat_read_rounded
              : Icons.mark_chat_unread_rounded,
          false,
          room.isUnread,
        ),
        (
          PeekMenuItem.pin,
          room.isFavourite ? l10n.unpin : l10n.pin,
          Icons.push_pin_rounded,
          false,
          room.isFavourite,
        ),
        (
          PeekMenuItem.mute,
          muted ? l10n.unmute : l10n.mute,
          muted ? Icons.notifications_rounded : Icons.notifications_off_rounded,
          false,
          muted,
        ),
        (
          PeekMenuItem.archive,
          room.isArchivedChat ? l10n.unarchive : l10n.archive,
          Icons.inventory_2_rounded,
          false,
          room.isArchivedChat,
        ),
        (PeekMenuItem.leave, l10n.leaveChat, Icons.logout_rounded, true, false),
        (
          PeekMenuItem.more,
          l10n.moreOptions,
          Icons.more_horiz_rounded,
          false,
          false,
        ),
      ];
      return SizedBox(
        width: 250,
        child: GlassSurface(
          blur: 24,
          solid: solid,
          borderRadius: BorderRadius.circular(22),
          shadows: AppElevation.menu,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, entry) in entries.indexed)
                  InkWell(
                    autofocus: i == 0,
                    onTap: () => onSelect(entry.$1, entry.$5),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 46),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          spacing: 16,
                          children: [
                            Icon(
                              entry.$3,
                              size: 22,
                              color: entry.$4 ? tokens.red : tokens.fg,
                            ),
                            Expanded(
                              child: Text(
                                entry.$2,
                                style: TextStyle(
                                  color: entry.$4 ? tokens.red : tokens.fg,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
