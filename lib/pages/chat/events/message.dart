// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/utd_why_sheet.dart';
import 'package:fluffychat/utils/appearance/chat_appearance_scope.dart';
import 'package:fluffychat/utils/chat/bubble_shape.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/chat/message_ticks.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/motion.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/member_actions_popup_menu_button.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'deleted_bubble_content.dart';
import 'message_bubble.dart';
import 'message_content.dart';
import 'message_focus.dart';
import 'message_footer.dart';
import 'message_hover_actions.dart';
import 'message_reactions.dart';
import 'reply_content.dart';
import 'state_message.dart';
import 'swipe_to_reply.dart';
import 'utd_bubble_content.dart';

class Message extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;
  final void Function(Event event, Rect anchor) onOpenMenu;
  final void Function(Event) onInfoTab;
  final void Function(Event)? onEditHistory;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final void Function() onMention;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final Timeline timeline;
  final bool highlightMarker;
  final bool animateIn;
  final bool wallpaperMode;
  final Tick tick;
  final bool Function(Event) isHighlight;
  final void Function()? onExpand;
  final bool isCollapsed;
  final Set<String> bigEmojis;

  const Message(
    this.event, {
    this.nextEvent,
    this.previousEvent,
    this.displayReadMarker = false,
    this.longPressSelect = false,
    required this.bigEmojis,
    required this.onSelect,
    required this.onOpenMenu,
    required this.onInfoTab,
    this.onEditHistory,
    required this.scrollToEventId,
    required this.onSwipe,
    this.selected = false,
    required this.timeline,
    this.highlightMarker = false,
    this.animateIn = false,
    this.wallpaperMode = false,
    this.tick = Tick.none,
    required this.isHighlight,
    required this.onMention,
    this.onExpand,
    required this.enterThread,
    this.isCollapsed = false,
    super.key,
  });

  static const _sameSenderTypes = {
    EventTypes.Message,
    EventTypes.Sticker,
    EventTypes.Encrypted,
  };

  bool _sameRun(Event? other) =>
      other != null &&
      _sameSenderTypes.contains(other.type) &&
      other.senderId == event.senderId &&
      other.originServerTs.sameEnvironment(event.originServerTs);

  @override
  Widget build(BuildContext context) {
    final undecryptable = event.isUndecryptable;
    final menuEnabled = !longPressSelect && !event.redacted;
    if (!undecryptable &&
        !{
          EventTypes.Message,
          EventTypes.Sticker,
          EventTypes.CallInvite,
          PollEventContent.startType,
        }.contains(event.type)) {
      if (event.type.startsWith('m.call.')) {
        return const SizedBox.shrink();
      }
      return StateMessage(event, onExpand: onExpand, isCollapsed: isCollapsed);
    }

    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return StateMessage(event);
    }

    final tokens = AppTokens.of(context);
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;
    final isDirect = event.room.isDirectChat;
    final nextEventSameSender = _sameRun(nextEvent);
    final previousEventSameSender = _sameRun(previousEvent);
    final displayEvent = event.getDisplayEvent(timeline);
    final kind = bubbleKind(displayEvent, own: ownMessage);
    final colors = BubbleColors.of(tokens, outgoing: ownMessage, kind: kind);
    final noBubble =
        ({
          MessageTypes.Video,
          MessageTypes.Image,
          MessageTypes.Sticker,
        }.contains(event.messageType) &&
        event.fileDescription == null &&
        !event.redacted);
    final mention =
        !ownMessage &&
        kind == BubbleKind.normal &&
        (isHighlight(event) ||
            (client.userID != null &&
                event.mentions.userIds.contains(client.userID)));
    final showSender = !nextEventSameSender && !ownMessage && !isDirect;
    final showAvatarColumn = !ownMessage && !isDirect;
    final hasReactions = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final threadChildren = event.aggregatedEvents(
      timeline,
      RelationshipTypes.thread,
    );
    final isEdited = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.edit,
    );
    final sender = event.senderFromMemoryOrFallback;
    final radius = bubbleRadius(
      outgoing: ownMessage,
      tail: !previousEventSameSender,
      corners: ChatAppearanceScope.cornersOf(context),
    );
    final direction = Directionality.of(context);
    final footer = MessageFooter(
      time: selected
          ? event.originServerTs.localizedDetailedTime(context)
          : event.originServerTs.localizedTimeOfDay(context),
      edited: isEdited,
      onEditedTap:
          isEdited &&
              onEditHistory != null &&
              !event.redacted &&
              !event.isUndecryptable
          ? () => onEditHistory!(event)
          : null,
      tick: ownMessage ? tick : Tick.none,
      color: noBubble ? Colors.white : colors.secondary,
    );

    final Widget content;
    switch (kind) {
      case BubbleKind.deleted:
        content = InkWell(
          onTap: () => onInfoTab(event),
          child: _DeletedContent(event: event),
        );
      case BubbleKind.undecryptable:
        content = UtdBubbleContent(
          onWhy: () => showUtdWhySheet(context, event),
        );
      case BubbleKind.normal:
      case BubbleKind.error:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.inReplyToEventId(includingFallback: false) != null)
              FutureBuilder<Event?>(
                future: event.getReplyEvent(timeline),
                builder: (context, snapshot) {
                  final replyEvent = snapshot.data;
                  final replyId = event.inReplyToEventId();
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 6,
                      top: 6,
                      end: 6,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: replyId == null
                          ? null
                          : () =>
                                scrollToEventId(replyEvent?.eventId ?? replyId),
                      child: AbsorbPointer(
                        child: replyEvent == null
                            ? ReplyQuoteView(
                                name: '…',
                                text: '…',
                                outgoing: ownMessage,
                              )
                            : ReplyContent(
                                replyEvent,
                                ownMessage: ownMessage,
                                timeline: timeline,
                              ),
                      ),
                    ),
                  );
                },
              ),
            MessageContent(
              displayEvent,
              textColor: colors.text,
              linkColor: colors.link,
              onInfoTab: onInfoTab,
              borderRadius: radius.resolve(direction),
              timeline: timeline,
              selected: selected,
              bigEmojis: bigEmojis,
            ),
          ],
        );
    }

    final bubbleMax = bubbleMaxWidth(
      MediaQuery.sizeOf(context).width.clamp(0, FluffyThemes.maxTimelineWidth),
    );
    final bubble = MessageBubble(
      kind: kind,
      outgoing: ownMessage,
      tail: !previousEventSameSender,
      mention: mention,
      transparent: noBubble,
      maxWidth: bubbleMax,
      child: noBubble
          ? Stack(
              children: [
                content,
                PositionedDirectional(
                  bottom: 6,
                  end: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.chip,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      child: footer,
                    ),
                  ),
                ),
              ],
            )
          : BubbleBody(
              content: content,
              footer: footer,
              width: displayEvent.messageType == MessageTypes.Location
                  ? math.min(bubbleMax, AppChat.mapBubbleWidth)
                  : null,
            ),
    );

    return Center(
      child: SwipeToReply(
        key: ValueKey(event.transactionId ?? event.eventId),
        rightToLeft: AppSettings.swipeRightToLeftToReply.value,
        onReply: onSwipe,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.maxTimelineWidth,
          ),
          padding: EdgeInsetsDirectional.only(
            start: 8.0,
            end: 8.0,
            top: nextEventSameSender ? 1.0 : 8.0,
            bottom: previousEventSameSender || previousEvent == null
                ? 1.0
                : 8.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: ownMessage
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: <Widget>[
              MessageHoverActions(
                enabled:
                    menuEnabled &&
                    event.room.canSendDefaultMessages &&
                    event.status.isSent,
                outgoing: ownMessage,
                onReact: () => _openMenuFrom(context),
                onReply: onSwipe,
                onMore: () => _openMenuFrom(context),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Material(
                        borderRadius: BorderRadius.circular(AppRadius.banner),
                        color: selected || highlightMarker
                            ? tokens.accs.withValues(alpha: 0.7)
                            : Colors.transparent,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: ownMessage
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      spacing: AppChat.groupGap,
                      children: [
                        if (longPressSelect &&
                            !event.redacted &&
                            !undecryptable)
                          SizedBox.square(
                            dimension: AppChat.jumpHit,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: L10n.of(context).select,
                              icon: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                              ),
                              onPressed: () => onSelect(event),
                            ),
                          )
                        else if (showAvatarColumn)
                          SizedBox(
                            width: AppChat.bubbleAvatar,
                            child: previousEventSameSender
                                ? null
                                : _SenderAvatar(
                                    event: event,
                                    fallback: sender,
                                    onMention: onMention,
                                    wallpaperMode: wallpaperMode,
                                  ),
                          ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: ownMessage
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showSender)
                                _SenderName(
                                  event: event,
                                  fallback: sender,
                                  brightness: theme.brightness,
                                ),
                              Builder(
                                builder: (bubbleContext) => MessageFocus(
                                  enabled: menuEnabled,
                                  actionLabel: L10n.of(context).moreOptions,
                                  onOpenMenu: () => _openMenu(bubbleContext),
                                  child: GestureDetector(
                                    onDoubleTap:
                                        menuEnabled &&
                                            AppSettings
                                                .doubleTapToReact
                                                .value &&
                                            event.room.canSendDefaultMessages
                                        ? () => _doubleTapReact(client)
                                        : null,
                                    onLongPress: menuEnabled
                                        ? () => _openMenu(bubbleContext)
                                        : null,
                                    onSecondaryTapUp: menuEnabled
                                        ? (_) => _openMenu(bubbleContext)
                                        : null,
                                    child: _AnimateIn(
                                      key: ValueKey(
                                        event.transactionId ?? event.eventId,
                                      ),
                                      animateIn: animateIn,
                                      child: KeyedSubtree(
                                        key: mention
                                            ? Key(
                                                'mention_ring_${event.eventId}',
                                              )
                                            : null,
                                        child: Semantics(
                                          hint: mention
                                              ? L10n.of(context).mentionsYou
                                              : null,
                                          child: bubble,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(
                                  0,
                                  -AppChat.reactionOverlap,
                                ),
                                child: AnimatedSize(
                                  duration: motionDuration(
                                    context,
                                    FluffyThemes.animationDuration,
                                  ),
                                  curve: FluffyThemes.animationCurve,
                                  alignment: ownMessage
                                      ? AlignmentDirectional.bottomEnd
                                      : AlignmentDirectional.bottomStart,
                                  child: hasReactions
                                      ? ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: bubbleMax,
                                          ),
                                          child: MessageReactions(
                                            event,
                                            timeline,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              if (event.status == EventStatus.error)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    top: 2,
                                  ),
                                  child: Text(
                                    L10n.of(context).couldNotBeSent,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tokens.red,
                                    ),
                                  ),
                                ),
                              if (event.status == EventStatus.sending &&
                                  event.fileSendingStatus != null)
                                Text(
                                  switch (event.fileSendingStatus!) {
                                    FileSendingStatus.generatingThumbnail =>
                                      L10n.of(context).generatingThumbnail,
                                    FileSendingStatus.encrypting => L10n.of(
                                      context,
                                    ).encrypting,
                                    FileSendingStatus.uploading => L10n.of(
                                      context,
                                    ).uploading,
                                  },
                                  style: TextStyle(
                                    color: tokens.mut,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (enterThread != null)
                AnimatedSize(
                  duration: motionDuration(
                    context,
                    FluffyThemes.animationDuration,
                  ),
                  curve: FluffyThemes.animationCurve,
                  alignment: Alignment.bottomCenter,
                  child: threadChildren.isEmpty
                      ? const SizedBox.shrink()
                      : _ThreadChip(
                          event: event,
                          children: threadChildren,
                          onTap: () => enterThread!(event.eventId),
                        ),
                ),
              if (displayReadMarker) const _ReadMarker(),
            ],
          ),
        ),
      ),
    );
  }

  void _openMenu(BuildContext bubbleContext) {
    HapticFeedback.heavyImpact();
    final box = bubbleContext.findRenderObject() as RenderBox?;
    if (event.status.isError || box == null || !box.attached) {
      onSelect(event);
      return;
    }
    onOpenMenu(event, box.localToGlobal(Offset.zero) & box.size);
  }

  void _openMenuFrom(BuildContext context) {
    Element? bubble;
    void visit(Element element) {
      if (bubble != null) return;
      if (element.widget is MessageBubble) {
        bubble = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    final box = bubble?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    onOpenMenu(event, box.localToGlobal(Offset.zero) & box.size);
  }

  void _doubleTapReact(Client client) {
    HapticFeedback.lightImpact();
    final emoji = AppSettings.doubleTapReaction.value;
    final existing = event
        .aggregatedEvents(timeline, RelationshipTypes.reaction)
        .firstWhereOrNull(
          (e) =>
              e.senderId == client.userID &&
              e.content
                      .tryGetMap<String, Object?>('m.relates_to')
                      ?.tryGet<String>('key') ==
                  emoji,
        );
    if (existing != null) {
      existing.redactEvent();
      return;
    }
    event.room.sendReaction(event.eventId, emoji);
  }
}

class _SenderName extends StatelessWidget {
  final Event event;
  final User fallback;
  final Brightness brightness;

  const _SenderName({
    required this.event,
    required this.fallback,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 2),
    child: FutureBuilder<User?>(
      future: event.fetchSenderUser(),
      builder: (context, snapshot) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          if (fallback.powerLevel.role != PowerLevelRole.user)
            Icon(
              fallback.powerLevel.role == PowerLevelRole.moderator
                  ? Icons.add_moderator_outlined
                  : Icons.admin_panel_settings,
              size: 14,
              color: event.senderId.nameColor(brightness),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                safeDisplayText(
                  snapshot.data?.calcDisplayname() ??
                      fallback.calcDisplayname(),
                  maxGraphemes: 64,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: event.senderId.nameColor(brightness),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SenderAvatar extends StatelessWidget {
  final Event event;
  final User fallback;
  final VoidCallback onMention;
  final bool wallpaperMode;

  const _SenderAvatar({
    required this.event,
    required this.fallback,
    required this.onMention,
    required this.wallpaperMode,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<User?>(
    future: event.fetchSenderUser(),
    builder: (context, snapshot) {
      final user = snapshot.data ?? fallback;
      return Avatar(
        mxContent: user.avatarUrl,
        name: user.calcDisplayname(),
        colorSeed: user.id,
        onTap: () => showMemberActionsPopupMenu(
          context: context,
          user: user,
          onMention: onMention,
        ),
        size: AppChat.bubbleAvatar,
        presenceUserId: user.stateKey,
        presenceSize: 12,
        presenceBorder: 2.5,
        presenceBackgroundColor: wallpaperMode ? Colors.transparent : null,
      );
    },
  );
}

class _DeletedContent extends StatelessWidget {
  final Event event;

  const _DeletedContent({required this.event});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final redaction = event.redactedBecause;
    return FutureBuilder<User?>(
      future: redaction?.fetchSenderUser(),
      builder: (context, snapshot) {
        final redactor = safeDisplayText(
          snapshot.data?.calcDisplayname() ??
              redaction?.senderId.localpart ??
              l10n.user,
          maxGraphemes: 40,
        );
        final byAuthor =
            redaction == null || redaction.senderId == event.senderId;
        final authorName = byAuthor
            ? safeDisplayText(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                maxGraphemes: 40,
              )
            : redactor;
        final reason = redaction?.content.tryGet<String>('reason');
        return DeletedBubbleContent(
          text: byAuthor
              ? l10n.userDeletedThisMessage(authorName)
              : reason == null
              ? l10n.redactedBy(redactor)
              : l10n.redactedByBecause(
                  redactor,
                  safeDisplayText(reason, maxGraphemes: 200),
                ),
        );
      },
    );
  }
}

class _ThreadChip extends StatelessWidget {
  final Event event;
  final Set<Event> children;
  final VoidCallback onTap;

  const _ThreadChip({
    required this.event,
    required this.children,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: 2.0,
        bottom: 8.0,
        start: AppChat.bubbleAvatar + AppChat.groupGap + 8,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.columnWidth * 1.5,
        ),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.banner),
            ),
            foregroundColor: tokens.acc,
            backgroundColor: tokens.accs,
          ),
          onPressed: onTap,
          icon: const Icon(Icons.message),
          label: Text(
            '${L10n.of(context).countReplies(children.length)} | ${children.first.calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)), withSenderNamePrefix: true)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _ReadMarker extends StatelessWidget {
  const _ReadMarker();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      children: [
        Expanded(child: Divider(color: tokens.line)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 16.0),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: tokens.chip,
          ),
          child: Text(
            L10n.of(context).readUpToHere,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(child: Divider(color: tokens.line)),
      ],
    );
  }
}

class _AnimateIn extends StatefulWidget {
  final bool animateIn;
  final Widget child;
  const _AnimateIn({required this.animateIn, required this.child, super.key});

  @override
  State<_AnimateIn> createState() => __AnimateInState();
}

class __AnimateInState extends State<_AnimateIn> {
  bool _animationFinished = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animateIn) return widget.child;
    if (!_animationFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _animationFinished = true;
        });
      });
    }

    return AnimatedSize(
      duration: motionDuration(context, FluffyThemes.animationDuration),
      curve: FluffyThemes.animationCurve,
      child: _animationFinished ? widget.child : const SizedBox.shrink(),
    );
  }
}
