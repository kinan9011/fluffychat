// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/chat_header.dart';
import 'package:fluffychat/pages/chat/chat_jump_buttons.dart';
import 'package:fluffychat/pages/chat/chat_wallpaper.dart';
import 'package:fluffychat/pages/chat/composer/attachment_type_bar.dart';
import 'package:fluffychat/pages/chat/composer/composer_panel_model.dart';
import 'package:fluffychat/pages/chat/composer/format_panel.dart';
import 'package:fluffychat/pages/chat/composer/quick_format_bar.dart';
import 'package:fluffychat/pages/chat/new_device_banner.dart';
import 'package:fluffychat/pages/chat/pinned_events.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/chat/new_device_banner_model.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/stream_extension.dart';
import 'chat_emoji_picker.dart';
import 'chat_input_row.dart';

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);

    final bottomSheetPadding = FluffyThemes.isColumnMode(context) ? 16.0 : 8.0;
    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    final accountConfig = Matrix.of(context).client.applicationAccountConfig;

    return PopScope(
      canPop:
          controller.selectedEvents.isEmpty &&
          !controller.showEmojiPicker &&
          controller.activeThreadId == null,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        if (controller.selectedEvents.isNotEmpty) {
          controller.clearSelectedEvents();
        } else if (controller.showEmojiPicker) {
          controller.emojiPickerAction();
        } else if (controller.activeThreadId != null) {
          controller.closeThread();
        }
      },
      child: StreamBuilder(
        stream: StreamGroup.merge<Object?>([
          controller.room.client.onRoomState.stream.where(
            (update) => update.roomId == controller.room.id,
          ),
          controller.room.client.onSync.stream.where(
            (update) => update.deviceLists != null,
          ),
        ]).rateLimit(const Duration(seconds: 1)),
        builder: (context, snapshot) => FutureBuilder(
          future: controller.loadTimelineFuture,
          builder: (BuildContext context, snapshot) {
            final activeThreadId = controller.activeThreadId;
            final showPinned =
                controller.room.pinnedEventIds.isNotEmpty &&
                activeThreadId == null;
            final showScrollUp =
                scrollUpBannerEventId != null && activeThreadId == null;
            final bannerCount =
                (activeThreadId != null ? 1 : 0) +
                (showPinned ? 1 : 0) +
                (showScrollUp ? 1 : 0);
            final newDevice = activeThreadId == null
                ? lookUpNewDeviceBanner(
                    controller.room,
                    dismissed: NewDeviceDismissals.keys,
                  )
                : null;
            final newDeviceHeight =
                AppChat.newDeviceBannerHeight *
                MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
            final topPadding = AppChat.listTopPadding(
              topInset: MediaQuery.paddingOf(context).top,
              bannerCount: bannerCount,
              bannerHeight: ChatAppBarListTile.fixedHeight + AppSpacing.s,
              extraHeight: newDevice == null
                  ? 0
                  : newDeviceHeight + AppSpacing.s,
            );
            final mentionCount = controller.unreadMentionCount;
            return Scaffold(
              key: Key('chat_page'),
              backgroundColor: tokens.bg,
              body: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (SizeChangedLayoutNotification notification) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => controller.updateInputBarHeight(),
                  );
                  return true;
                },
                child: DropTarget(
                  onDragDone: controller.onDragDone,
                  onDragEntered: controller.onDragEntered,
                  onDragExited: controller.onDragExited,
                  child: SafeArea(
                    top: false,
                    child: BackdropGroup(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: ChatWallpaper(config: accountConfig),
                            ),
                            GestureDetector(
                              onTap: controller.clearSingleSelectedEvent,
                              child: ChatEventList(
                                controller: controller,
                                topPadding: topPadding,
                              ),
                            ),
                            PositionedDirectional(
                              top: 0,
                              start: 0,
                              end: 0,
                              child: SafeArea(
                                bottom: false,
                                child: Column(
                                  children: [
                                    const SizedBox(
                                      height: AppChat.headerTopGap,
                                    ),
                                    ChatHeader(controller),
                                    if (newDevice != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: AppSpacing.m,
                                          right: AppSpacing.m,
                                          top: AppSpacing.s,
                                        ),
                                        child: NewDeviceBanner(
                                          name: controller.room
                                              .unsafeGetUserFromMemoryOrFallback(
                                                newDevice.userId,
                                              )
                                              .calcDisplayname(),
                                          height: newDeviceHeight,
                                          onVerify: () => context.go(
                                            '/rooms/${controller.room.id}/encryption',
                                          ),
                                          onDismiss: () {
                                            NewDeviceDismissals.dismiss(
                                              newDevice,
                                            );
                                            controller.refresh();
                                          },
                                        ),
                                      ),
                                    if (activeThreadId != null)
                                      _Banner(
                                        child: Center(
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                controller.scrollToEventId(
                                                  activeThreadId,
                                                ),
                                            icon: const Icon(Icons.message),
                                            label: Text(
                                              L10n.of(context).replyInThread,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (showPinned)
                                      _Banner(child: PinnedEvents(controller)),
                                    if (showScrollUp)
                                      _Banner(
                                        child: ChatAppBarListTile(
                                          leading: IconButton(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            icon: const Icon(Icons.close),
                                            tooltip: L10n.of(context).close,
                                            onPressed: () {
                                              controller
                                                  .discardScrollUpBannerEventId();
                                              controller.setReadMarker();
                                            },
                                          ),
                                          title: L10n.of(
                                            context,
                                          ).jumpToLastReadMessage,
                                          trailing: TextButton(
                                            onPressed: () {
                                              controller.scrollToEventId(
                                                scrollUpBannerEventId,
                                              );
                                              controller
                                                  .discardScrollUpBannerEventId();
                                            },
                                            child: Text(L10n.of(context).jump),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            PositionedDirectional(
                              end: AppSpacing.xl,
                              bottom:
                                  (controller.inputBarHeight ??
                                      AppChat.composerHeight) +
                                  AppSpacing.m,
                              child: ChatJumpButtons(
                                mentionCount: mentionCount,
                                unreadCount: controller.unreadBadgeCount,
                                showScrollDown:
                                    controller.showScrollDownButton &&
                                    controller.selectedEvents.isEmpty,
                                onMention: controller.jumpToNextMention,
                                onScrollDown: controller.scrollDown,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: SizeChangedLayoutNotifier(
                                child: Container(
                                  key: controller.inputBarKey,
                                  alignment: Alignment.center,
                                  child: Container(
                                    margin: EdgeInsets.fromLTRB(
                                      AppSpacing.m,
                                      0,
                                      AppSpacing.m,
                                      bottomSheetPadding,
                                    ),
                                    constraints: const BoxConstraints(
                                      maxWidth: FluffyThemes.maxTimelineWidth,
                                    ),
                                    child: _Composer(
                                      controller,
                                      availableHeight: constraints.maxHeight,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom:
                                  (controller.inputBarHeight ??
                                      AppChat.composerHeight) +
                                  AppSpacing.s,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: FluffyThemes.maxTimelineWidth,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.m,
                                    ),
                                    child: QuickFormatBar(
                                      controller: controller.sendController,
                                      focusNode: controller.inputFocus,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (controller.dragging)
                              Container(
                                color: theme.scaffoldBackgroundColor.withAlpha(
                                  230,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.upload_outlined,
                                  size: 100,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Widget child;

  const _Banner({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: AppSpacing.m,
      end: AppSpacing.m,
      top: AppSpacing.s,
    ),
    child: GlassSurface(
      borderRadius: BorderRadius.circular(AppRadius.banner),
      child: SizedBox(height: ChatAppBarListTile.fixedHeight, child: child),
    ),
  );
}

class _Composer extends StatelessWidget {
  final ChatController controller;
  final double availableHeight;

  const _Composer(this.controller, {required this.availableHeight});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final room = controller.room;
    if (room.isExtinct) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.chevron_right),
        label: Text(l10n.enterNewChat),
        onPressed: controller.goToNewRoomAction,
      );
    }
    if (!room.canSendDefaultMessages && room.membership != Membership.invite) {
      return const SizedBox.shrink();
    }
    if (room.membership == .invite) {
      return _GlassPillRow([
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.all(16),
              foregroundColor: tokens.red,
            ),
            icon: const Icon(Icons.cancel_outlined),
            onPressed: controller.leaveChat,
            label: Text(l10n.decline),
          ),
        ),
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
            icon: const Icon(Icons.check_outlined),
            onPressed: controller.joinChat,
            label: Text(l10n.accept),
          ),
        ),
      ]);
    }
    if (room.isAbandonedDMRoom == true) {
      return _GlassPillRow([
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.all(16),
              foregroundColor: tokens.red,
            ),
            icon: const Icon(Icons.archive_outlined),
            onPressed: controller.leaveChat,
            label: Text(l10n.leave),
          ),
        ),
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
            icon: const Icon(Icons.forum_outlined),
            onPressed: controller.recreateChat,
            label: Text(l10n.reopenChat),
          ),
        ),
      ]);
    }
    return Column(
      mainAxisSize: .min,
      children: [
        ReplyDisplay(controller),
        ValueListenableBuilder(
          valueListenable: controller.composerPanel,
          builder: (context, panel, _) => panel == ComposerPanel.format
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: FormatPanel(
                    controller: controller.sendController,
                    availableHeight: availableHeight,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ChatInputRow(controller),
        ValueListenableBuilder(
          valueListenable: controller.composerPanel,
          builder: (context, panel, _) => panel == ComposerPanel.attach
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s),
                  child: AttachmentTypeBar(
                    types: attachmentTypes(mobile: PlatformInfos.isMobile),
                    onSelected: controller.onAttachmentSelected,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ChatEmojiPicker(controller),
      ],
    );
  }
}

class _GlassPillRow extends StatelessWidget {
  final List<Widget> children;

  const _GlassPillRow(this.children);

  @override
  Widget build(BuildContext context) => GlassSurface(
    borderRadius: BorderRadius.circular(AppRadius.composer),
    child: Row(children: children),
  );
}
