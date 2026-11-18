// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/active_call_indicator.dart';
import 'package:fluffychat/pages/chat_list/swipe_action_row.dart';
import 'package:fluffychat/utils/chat_list/chat_row_model.dart';
import 'package:fluffychat/utils/chat_list/swipe_actions.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/motion.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

/// The last message of the chat, unless the chat's retention timer hides it.
Event? _lastVisibleEvent(Room room) {
  final event = room.lastEvent;
  if (event == null) return null;
  final retention = RetentionPolicy.forRoom(room);
  return retention?.hides(event, DateTime.now()) == true ? null : event;
}

class ChatListItem extends StatelessWidget {
  static const minHeight = 76.0;
  static const avatarSize = 56.0;

  final Room room;
  final Room? space;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function(BuildContext context)? onPeek;
  final void Function()? onForget;
  final void Function() onTap;
  final ChatRowActions? actions;
  final DraftStore? drafts;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onPeek,
    this.onForget,
    this.space,
    this.actions,
    this.drafts,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locals = MatrixLocals(l10n);
    final displayname = room.getLocalizedDisplayname(locals);
    final lastEvent = _lastVisibleEvent(room);
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final withSenderPrefix =
        !isDirectChat || directChatMatrixId != lastEvent?.senderId;
    final needLastEventSender =
        lastEvent != null &&
        room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;

    return FutureBuilder(
      future: room.name.isEmpty ? room.loadHeroUsers() : null,
      builder: (context, _) => FutureBuilder<RowPreview>(
        key: ValueKey(
          '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
        ),
        future: needLastEventSender
            ? RowPreview.load(lastEvent, locals, withSenderPrefix)
            : null,
        initialData: lastEvent == null
            ? null
            : RowPreview.fallback(lastEvent, locals, withSenderPrefix),
        builder: (context, snapshot) {
          final preview = _previewText(context, snapshot.data);
          final rowActions = actions;
          return ValueListenableBuilder<int>(
            valueListenable: DraftStore.revision,
            builder: (context, _, _) {
              final row = _RowBody(
                room: room,
                space: space,
                displayname: displayname,
                directChatMatrixId: directChatMatrixId,
                activeChat: activeChat,
                preview: snapshot.data,
                previewText: preview,
                draft: activeChat || room.membership != Membership.join
                    ? null
                    : drafts?.readForDisplay(room.id),
                onTap: onTap,
                onLongPress: onLongPress,
                onPeek: onPeek,
                onForget: onForget,
                actions: actions,
              );
              if (rowActions == null || !room.canSwipe) return row;
              return SwipeActionRow(
                key: ValueKey('swipe_${room.id}'),
                roomId: room.id,
                actions: rowActions,
                unread: room.isUnread,
                muted: room.pushRuleState != PushRuleState.notify,
                pinned: room.isFavourite,
                archived: room.isArchivedChat,
                child: row,
              );
            },
          );
        },
      ),
    );
  }

  String _previewText(BuildContext context, RowPreview? preview) {
    final l10n = L10n.of(context);
    if (room.membership == Membership.invite) {
      return room
              .getState(EventTypes.RoomMember, room.client.userID!)
              ?.content
              .tryGet<String>('reason') ??
          (room.directChatMatrixID != null
              ? l10n.newChatRequest
              : l10n.inviteGroupChat);
    }
    return preview?.text ?? l10n.noMessagesYet;
  }
}

class RowPreview {
  final String prefix;
  final String body;

  const RowPreview(this.prefix, this.body);

  String get text => '$prefix$body'.trim().replaceAll('\n', ' ');

  static RowPreview fallback(Event event, MatrixLocals locals, bool prefixed) {
    String body(bool withPrefix) => event.calcLocalizedBodyFallback(
      locals,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
      withSenderNamePrefix: withPrefix,
    );
    final plain = body(false);
    final full = prefixed ? body(true) : plain;
    return _split(full, plain);
  }

  static Future<RowPreview> load(
    Event event,
    MatrixLocals locals,
    bool prefixed,
  ) async {
    Future<String> body(bool withPrefix) => event.calcLocalizedBody(
      locals,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
      withSenderNamePrefix: withPrefix,
    );
    final plain = await body(false);
    final full = prefixed ? await body(true) : plain;
    return _split(full, plain);
  }

  static RowPreview _split(String full, String plain) =>
      full.length > plain.length && full.endsWith(plain)
      ? RowPreview(full.substring(0, full.length - plain.length), plain)
      : RowPreview('', full);
}

class _RowBody extends StatelessWidget {
  final Room room;
  final Room? space;
  final String displayname;
  final String? directChatMatrixId;
  final bool activeChat;
  final RowPreview? preview;
  final String previewText;
  final String? draft;
  final void Function() onTap;
  final void Function(BuildContext context)? onLongPress;
  final void Function(BuildContext context)? onPeek;
  final void Function()? onForget;
  final ChatRowActions? actions;

  const _RowBody({
    required this.room,
    required this.space,
    required this.displayname,
    required this.directChatMatrixId,
    required this.activeChat,
    required this.preview,
    required this.previewText,
    required this.draft,
    required this.onTap,
    required this.onLongPress,
    required this.onPeek,
    required this.onForget,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final isMuted = room.pushRuleState != PushRuleState.notify;
    final lastEvent = room.lastEvent;
    final typingText = room.getLocalizedTypingText(context);
    final isInvite = room.membership == Membership.invite;
    final bigText = MediaQuery.textScalerOf(context).scale(16) > 20.8;
    final time = isInvite || room.isSpace
        ? ''
        : room.latestEventReceivedTime.localizedTimeShort(context);
    final pinned = room.isFavourite;
    final semantics = chatRowSemantics(
      l10n,
      name: displayname,
      unread: room.notificationCount,
      preview: draft == null
          ? previewText
          : '${l10n.draftPrefix} ${DraftStore.preview(draft!)}',
      time: time,
      pinned: pinned,
      muted: isMuted,
      markedUnread: room.isUnreadOrInvited,
      mentioned: room.highlightCount > 0,
    );
    final actions = this.actions;
    final onForget = this.onForget;
    final customActions = <CustomSemanticsAction, VoidCallback>{
      if (actions != null && room.canSwipe) ...{
        CustomSemanticsAction(label: isMuted ? l10n.unmute : l10n.mute): () =>
            actions.run(room.id, SwipeAction.mute),
        CustomSemanticsAction(label: pinned ? l10n.unpin : l10n.pin): () =>
            actions.run(room.id, SwipeAction.pin),
        CustomSemanticsAction(
          label: room.isArchivedChat ? l10n.unarchive : l10n.archive,
        ): () =>
            actions.run(room.id, SwipeAction.archive),
        CustomSemanticsAction(
          label: room.isUnread ? l10n.markAsRead : l10n.markAsUnread,
        ): () =>
            actions.run(room.id, SwipeAction.toggleRead),
        CustomSemanticsAction(label: l10n.peek): () =>
            actions.peek(room.id, context),
        CustomSemanticsAction(label: l10n.moreOptions): () =>
            actions.more(room.id, context),
      },
      CustomSemanticsAction(label: l10n.delete): ?onForget,
    };

    return HoverBuilder(
      builder: (context, hovered) {
        final background = activeChat
            ? tokens.accs
            : hovered
            ? tokens.surf2
            : tokens.bg;
        return Semantics(
          container: true,
          label: semantics,
          onTap: onTap,
          customSemanticsActions: customActions.isEmpty ? null : customActions,
          excludeSemantics: true,
          child: Material(
            color: background,
            child: InkWell(
              onTap: onTap,
              onLongPress: () => (onPeek ?? onLongPress)?.call(context),
              onSecondaryTapUp: (_) => onLongPress?.call(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ChatListItem.minHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      _RowAvatar(
                        room: room,
                        space: space,
                        displayname: displayname,
                        directChatMatrixId: directChatMatrixId,
                        background: background,
                        hovered: hovered,
                        onMore: onLongPress,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          spacing: 4,
                          children: [
                            Row(
                              spacing: 4,
                              children: [
                                Expanded(
                                  child: Row(
                                    spacing: 4,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          displayname,
                                          maxLines: bigText ? 2 : 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: tokens.fg,
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (isMuted)
                                        Icon(
                                          Icons.volume_off_rounded,
                                          size: 16,
                                          color: tokens.mut,
                                        ),
                                      if (room.isLowPriority)
                                        Icon(
                                          Icons.low_priority,
                                          size: 16,
                                          color: tokens.mut,
                                        ),
                                    ],
                                  ),
                                ),
                                _Tick(
                                  tick: tickFor(lastEvent, room.client.userID),
                                ),
                                Text(
                                  time,
                                  style: TextStyle(
                                    color: tokens.mut,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              spacing: 6,
                              children: [
                                if (room.hasActiveMatrixRtcCall)
                                  ActiveCallIndicator(room: room),
                                Expanded(
                                  child: _Line2(
                                    typingText: typingText,
                                    preview: preview,
                                    previewText: previewText,
                                    draft: draft,
                                    hovered: hovered,
                                    redacted: lastEvent?.redacted == true,
                                    isThread:
                                        lastEvent?.relationshipType ==
                                        RelationshipTypes.thread,
                                  ),
                                ),
                                _Badges(room: room, muted: isMuted),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onForget != null)
                        IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_outlined),
                          onPressed: onForget,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RowAvatar extends StatelessWidget {
  final Room room;
  final Room? space;
  final String displayname;
  final String? directChatMatrixId;
  final Color background;
  final bool hovered;
  final void Function(BuildContext context)? onMore;

  const _RowAvatar({
    required this.room,
    required this.space,
    required this.displayname,
    required this.directChatMatrixId,
    required this.background,
    required this.hovered,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final space = this.space;
    const small = ChatListItem.avatarSize * 0.75;
    return SizedBox(
      width: ChatListItem.avatarSize,
      height: ChatListItem.avatarSize,
      child: Stack(
        children: [
          if (space != null)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Avatar(
                client: room.client,
                shapeBorder: RoundedSuperellipseBorder(
                  side: BorderSide(width: 2, color: background),
                  borderRadius: BorderRadius.circular(
                    AppConfig.spaceBorderRadius * 0.75,
                  ),
                ),
                borderRadius: BorderRadius.circular(
                  AppConfig.spaceBorderRadius * 0.75,
                ),
                mxContent: space.avatar,
                size: small,
                name: space.getLocalizedDisplayname(),
                colorSeed: space.id,
                onTap: () => onMore?.call(context),
              ),
            ),
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Avatar(
              client: room.client,
              shapeBorder: space == null
                  ? null
                  : RoundedRectangleBorder(
                      side: BorderSide(width: 2, color: background),
                      borderRadius: BorderRadius.circular(
                        ChatListItem.avatarSize,
                      ),
                    ),
              borderRadius: room.isSpace
                  ? BorderRadius.circular(AppConfig.spaceBorderRadius)
                  : null,
              mxContent: room.avatar,
              colorSeed: room.avatarColorSeed,
              size: space != null ? small : ChatListItem.avatarSize,
              name: displayname,
              presenceUserId: directChatMatrixId,
              presenceBackgroundColor: background,
              presenceSize: 15,
              presenceBorder: 2.5,
              onTap: () => onMore?.call(context),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: GestureDetector(
              onTap: () => onMore?.call(context),
              child: AnimatedScale(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 150),
                ),
                scale: hovered ? 1.0 : 0.0,
                child: Material(
                  color: background,
                  borderRadius: BorderRadius.circular(16),
                  child: const Icon(
                    Icons.arrow_drop_down_circle_outlined,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final RowTick tick;

  const _Tick({required this.tick});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return switch (tick) {
      RowTick.none => const SizedBox.shrink(),
      RowTick.sending => Icon(
        Icons.schedule_rounded,
        size: 17,
        color: tokens.mut,
      ),
      RowTick.sent => Icon(Icons.done_rounded, size: 17, color: tokens.acc),
      RowTick.read => Icon(Icons.done_all_rounded, size: 17, color: tokens.acc),
      RowTick.error => Icon(
        Icons.error_outline_rounded,
        size: 17,
        color: tokens.red,
      ),
    };
  }
}

class _Line2 extends StatelessWidget {
  final String typingText;
  final RowPreview? preview;
  final String previewText;
  final String? draft;
  final bool hovered;
  final bool redacted;
  final bool isThread;

  const _Line2({
    required this.typingText,
    required this.preview,
    required this.previewText,
    required this.draft,
    required this.hovered,
    required this.redacted,
    required this.isThread,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final style = TextStyle(color: tokens.mut, fontSize: 14.5, height: 1.3);
    if (typingText.isNotEmpty) {
      return Row(
        spacing: 4,
        children: [
          TypingAnimation(size: 4.0),
          Expanded(
            child: Text(
              typingText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: tokens.acc),
            ),
          ),
        ],
      );
    }
    final draft = this.draft;
    if (draft != null) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${L10n.of(context).draftPrefix} ',
              style: TextStyle(color: hovered ? tokens.fg : tokens.red),
            ),
            TextSpan(text: DraftStore.preview(draft)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final prefix = preview?.prefix ?? '';
    final usePrefix =
        prefix.isNotEmpty && preview != null && preview!.text == previewText;
    return Row(
      spacing: 6,
      children: [
        if (isThread)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.mut),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(Icons.message_outlined, size: 12, color: tokens.mut),
                Text(
                  L10n.of(context).thread,
                  style: TextStyle(fontSize: 11, color: tokens.mut),
                ),
              ],
            ),
          ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (usePrefix)
                  TextSpan(
                    text: prefix.replaceAll('\n', ' '),
                    style: TextStyle(color: tokens.fg),
                  ),
                TextSpan(
                  text: usePrefix
                      ? preview!.body.replaceAll('\n', ' ')
                      : previewText,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              decoration: redacted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badges extends StatelessWidget {
  final Room room;
  final bool muted;

  const _Badges({required this.room, required this.muted});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final count = room.notificationCount;
    final isInvite = room.membership == Membership.invite;
    final fill = muted ? tokens.mbad : tokens.acc;
    final onFill = muted ? Colors.white : tokens.onacc;
    final showPin = room.isFavourite && count == 0 && !room.isUnreadOrInvited;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (showPin)
          Transform.rotate(
            angle: 0.785398,
            child: Icon(Icons.push_pin_rounded, size: 17, color: tokens.mut),
          ),
        if (room.highlightCount > 0)
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: tokens.acc,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.alternate_email_rounded,
              size: 15,
              color: tokens.onacc,
            ),
          ),
        if (count > 0)
          Container(
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: TextStyle(
                color: onFill,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (count == 0 && (room.markedUnread || isInvite))
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          ),
      ],
    );
  }
}
