// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/edit_history_sheet.dart';
import 'package:fluffychat/pages/chat/encryption_info.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/message_menu.dart';
import 'package:fluffychat/pages/chat/seen_by_row.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/chat/message_ticks.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../config/app_config.dart';
import '../../utils/date_time_extension.dart';

class ChatEventList extends StatelessWidget {
  final ChatController controller;
  final double topPadding;

  const ChatEventList({
    super.key,
    required this.controller,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;

    if (controller.room.membership == .invite) {
      final room = controller.room;
      final inviteState = room.unsafeGetUserFromMemoryOrFallback(
        room.client.userID!,
      );
      final sender = room
          .unsafeGetUserFromMemoryOrFallback(inviteState.senderId)
          .calcDisplayname();
      final nameOrAlias = room.name.isNotEmpty
          ? room.name
          : room.canonicalAlias.isNotEmpty
          ? room.canonicalAlias
          : null;
      final roomAvatar = room.avatar;

      return Center(
        child: Container(
          padding: const EdgeInsets.all(32.0),
          alignment: .center,
          constraints: BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisAlignment: .center,
            crossAxisAlignment: .center,
            spacing: 16,
            children: [
              Avatar(
                mxContent: roomAvatar,
                name: room.getLocalizedDisplayname(),
                colorSeed: room.avatarColorSeed,
                size: Avatar.defaultSize * 2.5,
                onTap: roomAvatar != null
                    ? () => showDialog(
                        context: context,
                        builder: (_) => MxcImageViewer(roomAvatar),
                      )
                    : null,
                borderRadius: room.isSpace
                    ? BorderRadius.circular(AppConfig.spaceBorderRadius * 2.5)
                    : null,
              ),
              Text(
                nameOrAlias == null
                    ? L10n.of(context).youInvitedBy(sender)
                    : room.isSpace
                    ? L10n.of(
                        context,
                      ).senderHasInvitedYouToTheSpace(sender, nameOrAlias)
                    : L10n.of(
                        context,
                      ).senderHasInvitedYouToTheChat(sender, nameOrAlias),
                textAlign: .center,
              ),
            ],
          ),
        ),
      );
    }

    if (timeline == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final horizontalPadding = FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

    final events = timeline.events.filterByVisibleInGui(
      threadId: controller.activeThreadId,
      retention: controller.retention,
    );
    final tokens = AppTokens.of(context);
    final client = controller.room.client;
    final ticks = ownMessageTicks(events, client.userID);
    bool isHighlight(Event event) =>
        client.pushruleEvaluator.match(event).highlight;

    // create a map of eventId --> index to greatly improve performance of
    // ListView's findChildIndexCallback
    final thisEventsKeyMap = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      thisEventsKeyMap[events[i].eventId] = i;
    }

    final hasWallpaper =
        AppSettings.chatWallpaperLocal.value ||
        controller.room.client.applicationAccountConfig.wallpaperUrl != null;

    return SelectionArea(
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value),
        ),
        child: ListView.custom(
          padding: EdgeInsetsDirectional.only(
            top: 8 + topPadding,
            bottom:
                8 +
                (controller.inputBarHeight ??
                    (72 + (FluffyThemes.isColumnMode(context) ? 16 : 0))),
            start: horizontalPadding,
            end: horizontalPadding,
          ),
          reverse: true,
          controller: controller.scrollController,
          keyboardDismissBehavior: PlatformInfos.isIOS
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
          childrenDelegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              // Footer to display typing indicator and read receipts:
              if (i == 0) {
                if (timeline.canRequestFuture) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: timeline.isRequestingFuture
                          ? null
                          : controller.requestFuture,
                      icon: timeline.isRequestingFuture
                          ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                          : const Icon(Icons.arrow_downward_outlined),
                      label: Text(L10n.of(context).loadMore),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: .min,
                  children: [
                    if (events.isNotEmpty)
                      SeenByRow(event: events.first, timeline: timeline),
                    TypingIndicators(controller),
                    EncryptionInfo(room: controller.room),
                  ],
                );
              }

              // Request history button or progress indicator:
              if (i == events.length + 1) {
                if (controller.activeThreadId != null ||
                    !timeline.canRequestHistory) {
                  return const SizedBox.shrink();
                }
                return Builder(
                  builder: (context) {
                    final visibleIndex = timeline.events.lastIndexWhere(
                      (event) =>
                          !event.isCollapsedState && event.isVisibleInGui,
                    );
                    if (visibleIndex > timeline.events.length - 50) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        controller.requestHistory,
                      );
                    }
                    return Center(
                      child: TextButton.icon(
                        onPressed: timeline.isRequestingHistory
                            ? null
                            : controller.requestHistory,
                        icon: timeline.isRequestingHistory
                            ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                            : const Icon(Icons.arrow_upward_outlined),
                        label: Text(L10n.of(context).loadMore),
                      ),
                    );
                  },
                );
              }
              i--;

              // The message at this index:
              final event = events[i];
              final animateIn =
                  (event.transactionId ?? event.eventId) ==
                  controller.animateInEventId;

              final nextEvent = i + 1 < events.length ? events[i + 1] : null;
              final previousEvent = i > 0 ? events[i - 1] : null;

              // Collapsed state event
              final canExpand =
                  event.isCollapsedState &&
                  nextEvent?.isCollapsedState == true &&
                  previousEvent?.isCollapsedState != true;
              final isCollapsed =
                  event.isCollapsedState &&
                  previousEvent?.isCollapsedState == true &&
                  !controller.expandedEventIds.contains(event.eventId);

              final displayDate =
                  event.type == EventTypes.RoomCreate ||
                  nextEvent == null ||
                  !event.originServerTs.sameDay(nextEvent.originServerTs);

              return AutoScrollTag(
                key: ValueKey(event.transactionId ?? event.eventId),
                index: i,
                controller: controller.scrollController,
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    if (!isCollapsed && displayDate)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: 8.0,
                          bottom: 16.0,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(top: 4.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: tokens.chip,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 4,
                                ),
                                child: Text(
                                  event.originServerTs.localizedDate(context),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Message(
                      event,
                      bigEmojis: controller.bigEmojis,
                      animateIn: animateIn,
                      onSwipe: () => controller.replyAction(replyTo: event),
                      onInfoTab: controller.showEventInfo,
                      onEditHistory: (event) =>
                          showEditHistorySheet(context, controller, event),
                      onMention: () => controller.sendController.text +=
                          '${event.senderFromMemoryOrFallback.mention} ',
                      highlightMarker:
                          controller.scrollToEventIdMarker == event.eventId,
                      onSelect: controller.onSelectMessage,
                      onOpenMenu: (event, anchor) => showMessageMenu(
                        context: context,
                        controller: controller,
                        event: event,
                        anchor: anchor,
                        outgoing: event.senderId == client.userID,
                        timeline: timeline,
                      ),
                      scrollToEventId: controller.scrollToEventId,
                      longPressSelect: controller.selectedEvents.isNotEmpty,
                      selected: controller.selectedEvents.any(
                        (e) => e.eventId == event.eventId,
                      ),
                      timeline: timeline,
                      displayReadMarker:
                          i > 0 &&
                          controller.readMarkerEventId == event.eventId,
                      nextEvent: nextEvent,
                      previousEvent: previousEvent,
                      wallpaperMode: hasWallpaper,
                      tick:
                          ticks[event.transactionId ?? event.eventId] ??
                          Tick.none,
                      isHighlight: isHighlight,
                      isCollapsed: isCollapsed,
                      enterThread: controller.activeThreadId == null
                          ? controller.enterThread
                          : null,
                      onExpand: canExpand
                          ? () => controller.expandEventsFrom(
                              event,
                              !controller.expandedEventIds.contains(
                                event.eventId,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              );
            },
            childCount: events.length + 2,
            findChildIndexCallback: (key) =>
                controller.findChildIndexCallback(key, thisEventsKeyMap),
          ),
        ),
      ),
    );
  }
}
