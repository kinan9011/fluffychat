// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/archived_chats_row.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/chat_list_tabs.dart';
import 'package:fluffychat/pages/chat_list/chat_list_top_bar.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/folder_tab_actions.dart';
import 'package:fluffychat/pages/chat_list/key_backup_banner.dart';
import 'package:fluffychat/pages/chat_list/space_switcher.dart';
import 'package:fluffychat/utils/chat_list/folder_filter.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/chat_list/folder_store.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/own_avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

class ChatListViewBody extends StatelessWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final spaces = client.rooms.where((r) => r.isSpace);
    final spaceDelegateCandidates = <String, Room>{};
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    const dummyChatCount = 4;
    final l10n = L10n.of(context);
    final drafts = DraftStore.of(client);
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.spaceNavigation.listenable,
        AppSettings.showFoldersAfterSpaces.listenable,
        AppSettings.showTabUnreadCounts.listenable,
        AppSettings.hideRoomsInSpaces.listenable,
        Matrix.of(context).callsAvailability,
      ]),
      builder: (context, _) => StreamBuilder(
        key: ValueKey(client.userID.toString()),
        stream: client.onSync.stream
            .where((s) => s.hasRoomUpdate)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, _) {
          final mode = SpaceNavigationMode.fromSetting(
            AppSettings.spaceNavigation.value,
          );
          final spaceModel = SpaceTabsModel.build(
            client.rooms,
            nameOf: (room) => room.getLocalizedDisplayname(MatrixLocals(l10n)),
          );
          final userFolders = FolderStore.of(client).folders;
          final folderContext = FolderContext(
            spaces: spaceModel,
            userFolders: userFolders,
            hideRoomsInSpaces: AppSettings.hideRoomsInSpaces.value,
          );
          final scope = controller.scope;
          final items = FolderFilter.tabs(
            mode: mode,
            spaces: spaceModel.tabs,
            tags: controller.roomTags.keys.toList(),
            userFolders: userFolders,
            showFoldersAfterSpaces: AppSettings.showFoldersAfterSpaces.value,
            currentSpaceId: scope.spaceId,
          );
          final scopeIsShown =
              (scope.spaceId == null ||
                  spaceModel.tabs.any((tab) => tab.spaceId == scope.spaceId)) &&
              items.any(
                (item) => item.scope == scope.copyWith(archived: false),
              );
          if (client.prevBatch != null && !scopeIsShown) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.mounted) controller.resetScope();
            });
          }
          final rooms = FolderFilter.apply(client.rooms, scope, folderContext);
          final archivedRooms = scope.archived || scope.folder != FolderRef.all
              ? const <Room>[]
              : FolderFilter.apply(
                  client.rooms,
                  scope.copyWith(archived: true),
                  folderContext,
                );
          if (client.prevBatch != null && scope.archived && rooms.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.mounted && controller.scope.archived) {
                controller.closeArchived();
              }
            });
          }
          final showArchivedRow = archivedRooms.isNotEmpty;
          final unreadRooms = client.rooms
              .where((room) => room.isUnreadOrInvited)
              .toList();
          final tabs = chatListTabData(
            items,
            l10n: l10n,
            mode: mode,
            showCounts: AppSettings.showTabUnreadCounts.value,
            countOf: (tabScope) =>
                FolderFilter.unreadCount(unreadRooms, tabScope, folderContext),
          );

          return CustomScrollView(
            controller: controller.scrollController,
            slivers: [
              switch (scope.archived) {
                true => SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: _ArchivedHeader(onBack: controller.closeArchived),
                  ),
                ),
                false => SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        _TopBar(
                          controller: controller,
                          client: client,
                          mode: mode,
                          spaces: spaceModel.tabs,
                        ),
                        if (client.rooms.isNotEmpty)
                          ChatListTabBar(
                            client: client,
                            tabs: tabs,
                            selected: scope,
                            onSelect: controller.selectTab,
                            onLongPress: (tab) {
                              final spaceId = tab.space?.spaceId;
                              if (spaceId != null) {
                                controller.spaceTabAction(spaceId);
                                return;
                              }
                              final folderId = tab.scope.folder.value;
                              if (tab.scope.folder.kind != FolderKind.user ||
                                  folderId == null) {
                                return;
                              }
                              showUserFolderTabMenu(context, client, folderId);
                            },
                          ),
                        KeyBackupBanner(
                          key: ValueKey(client.clientName),
                          client: client,
                        ),
                      ],
                    ),
                  ),
                ),
              },
              SliverList(
                delegate: SliverChildListDelegate([
                  if (client.prevBatch != null && rooms.isEmpty) ...[
                    Column(
                      mainAxisAlignment: .center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            const Column(
                              mainAxisSize: .min,
                              children: [
                                DummyChatListItem(opacity: 0.5, animate: false),
                                DummyChatListItem(opacity: 0.3, animate: false),
                              ],
                            ),
                            Icon(
                              CupertinoIcons.chat_bubble_text_fill,
                              size: 128,
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            client.rooms.isEmpty
                                ? L10n.of(context).noChatsFoundHere
                                : L10n.of(context).noMoreChatsFound,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ]),
              ),
              if (client.prevBatch == null)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => DummyChatListItem(
                      opacity: (dummyChatCount - i) / dummyChatCount,
                      animate: true,
                    ),
                    childCount: dummyChatCount,
                  ),
                ),
              if (client.prevBatch != null)
                SliverSafeArea(
                  top: false,
                  sliver: SliverList.builder(
                    itemCount: rooms.length + (showArchivedRow ? 1 : 0),
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      final index = rooms.indexWhere(
                        (room) => key.value == 'chat_list_item_${room.id}',
                      );
                      return index < 0
                          ? null
                          : index + (showArchivedRow ? 1 : 0);
                    },
                    itemBuilder: (BuildContext context, int i) {
                      if (showArchivedRow && i == 0) {
                        return ArchivedChatsRow(
                          key: const ValueKey('archived_chats_row'),
                          count: archivedRooms.length,
                          names: archivedRooms
                              .take(ArchivedChatsRow.maxNames)
                              .map(
                                (room) => room.getLocalizedDisplayname(
                                  MatrixLocals(l10n),
                                ),
                              )
                              .toList(),
                          onTap: () => controller.selectTab(
                            scope.copyWith(archived: true),
                          ),
                        );
                      }
                      final room = rooms[i - (showArchivedRow ? 1 : 0)];
                      final space = spaceDelegateCandidates[room.id];
                      return ChatListItem(
                        room,
                        space: space,
                        key: ValueKey('chat_list_item_${room.id}'),
                        actions: controller.rowActions,
                        drafts: drafts,
                        onTap: () => controller.onChatTap(room),
                        onLongPress: (context) =>
                            controller.chatContextAction(room, context, space),
                        onPeek: room.canSwipe
                            ? (context) =>
                                  controller.rowActions.peek(room.id, context)
                            : null,
                        activeChat: controller.activeChat == room.id,
                        showCallIndicator: Matrix.of(
                          context,
                        ).callsAvailableFor(client),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ArchivedHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _ArchivedHeader({required this.onBack});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 16, 8),
    child: Row(
      children: [
        BackButton(onPressed: onBack),
        Expanded(
          child: Text(
            L10n.of(context).archivedChats,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTokens.of(context).fg,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  final ChatListController controller;
  final Client client;
  final SpaceNavigationMode mode;
  final List<SpaceTab> spaces;

  const _TopBar({
    required this.controller,
    required this.client,
    required this.mode,
    required this.spaces,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: client.onSyncStatus.stream,
    builder: (context, _) {
      final status =
          client.onSyncStatus.value ??
          const SyncStatusUpdate(SyncStatus.waitingForResponse);
      final synced =
          client.onSync.value != null &&
          status.status != SyncStatus.error &&
          client.prevBatch != null;
      return ChatListTopBar(
        title: AppSettings.applicationName.value,
        avatar: const OwnAvatar(size: 35),
        onProfile: () => context.go('/profile'),
        onSearch: controller.startSearch,
        overflow: ClientChooserButton(controller, overflowIcon: true),
        syncStatus: synced ? null : status,
        spaceChip: mode == SpaceNavigationMode.switcher
            ? SpaceSwitcherChip(
                client: client,
                spaces: spaces,
                selectedSpaceId: controller.scope.spaceId,
                onSelect: controller.selectSpace,
                onCreateSpace: () => context.go('/rooms/newspace'),
                onExplore: controller.explorePublic,
              )
            : null,
      );
    },
  );
}
