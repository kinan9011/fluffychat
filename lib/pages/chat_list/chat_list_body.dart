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
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_switcher.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/utils/chat_list/folder_filter.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/chat_list/folder_store.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/own_avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/matrix.dart';
import 'chat_list_header.dart';

class ChatListViewBody extends StatelessWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final overview = controller.overviewSpaceId;
    if (overview != null) {
      return SpaceView(
        key: ValueKey(overview),
        spaceId: overview,
        onBack: controller.closeSpaceOverview,
        onChatTab: controller.onChatTap,
        activeChat: controller.activeChat,
      );
    }
    final spaces = client.rooms.where((r) => r.isSpace);
    final spaceDelegateCandidates = <String, Room>{};
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    final publicRooms = controller.roomSearchResult?.chunk
        .where((room) => room.roomType != 'm.space')
        .toList();
    final publicSpaces = controller.roomSearchResult?.chunk
        .where((room) => room.roomType == 'm.space')
        .toList();
    final userSearchResult = controller.userSearchResult;
    const dummyChatCount = 4;
    final filter = controller.searchController.text.toLowerCase();
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final drafts = DraftStore(matrix.store);
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.spaceNavigation.listenable,
        AppSettings.showFoldersAfterSpaces.listenable,
        AppSettings.showTabUnreadCounts.listenable,
        AppSettings.hideRoomsInSpaces.listenable,
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
          // Drafts are stored by room id only, so a draft typed as another
          // account must not show up in this account's list.
          bool sharedWithOtherAccount(Room room) => matrix.widget.clients.any(
            (other) =>
                !identical(other, client) &&
                other.getRoomById(room.id)?.membership == Membership.join,
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
          final showArchivedRow =
              archivedRooms.isNotEmpty && !controller.isSearchMode;
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
              switch ((controller.isSearchMode, scope.archived)) {
                (true, _) => ChatListHeader(controller: controller),
                (_, true) => SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: _ArchivedHeader(onBack: controller.closeArchived),
                  ),
                ),
                _ => SliverToBoxAdapter(
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
                  if (controller.isSearchMode) ...[
                    SearchTitle(
                      title: L10n.of(context).publicRooms,
                      icon: const Icon(Icons.explore_outlined),
                    ),
                    PublicRoomsHorizontalList(publicRooms: publicRooms),
                    SearchTitle(
                      title: L10n.of(context).publicSpaces,
                      icon: const Icon(Icons.workspaces_outlined),
                    ),
                    PublicRoomsHorizontalList(publicRooms: publicSpaces),
                    SearchTitle(
                      title: L10n.of(context).users,
                      icon: const Icon(Icons.group_outlined),
                    ),
                    AnimatedContainer(
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      height:
                          userSearchResult == null ||
                              userSearchResult.results.isEmpty
                          ? 0
                          : 106,
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      child: userSearchResult == null
                          ? null
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: userSearchResult.results.length,
                              itemBuilder: (context, i) => _SearchItem(
                                title:
                                    userSearchResult.results[i].displayName ??
                                    userSearchResult
                                        .results[i]
                                        .userId
                                        .localpart ??
                                    L10n.of(context).unknownDevice,
                                colorSeed: userSearchResult.results[i].userId,
                                avatar: userSearchResult.results[i].avatarUrl,
                                onPressed: () => UserDialog.show(
                                  context: context,
                                  profile: userSearchResult.results[i],
                                ),
                              ),
                            ),
                    ),
                  ],
                  if (controller.isSearchMode)
                    SearchTitle(
                      title: L10n.of(context).chats,
                      icon: const Icon(Icons.forum_outlined),
                    ),
                  if (client.prevBatch != null &&
                      rooms.isEmpty &&
                      !controller.isSearchMode) ...[
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
                        filter: filter,
                        actions: controller.rowActions,
                        drafts: sharedWithOtherAccount(room) ? null : drafts,
                        onTap: () => controller.onChatTap(room),
                        onLongPress: (context) =>
                            controller.chatContextAction(room, context, space),
                        onPeek: room.canSwipe
                            ? (context) =>
                                  controller.rowActions.peek(room.id, context)
                            : null,
                        activeChat: controller.activeChat == room.id,
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
                onExplore: controller.startSearch,
              )
            : null,
      );
    },
  );
}

class PublicRoomsHorizontalList extends StatelessWidget {
  const PublicRoomsHorizontalList({super.key, required this.publicRooms});

  final List<PublishedRoomsChunk>? publicRooms;

  @override
  Widget build(BuildContext context) {
    final publicRooms = this.publicRooms;
    return AnimatedContainer(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: publicRooms == null || publicRooms.isEmpty ? 0 : 106,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: publicRooms == null
          ? null
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: publicRooms.length,
              itemBuilder: (context, i) => _SearchItem(
                title:
                    publicRooms[i].name ??
                    publicRooms[i].canonicalAlias?.localpart ??
                    L10n.of(context).group,
                colorSeed: publicRooms[i].roomId,
                avatar: publicRooms[i].avatarUrl,
                onPressed: () => showAdaptiveDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (c) => PublicRoomDialog(
                    roomAlias:
                        publicRooms[i].canonicalAlias ?? publicRooms[i].roomId,
                    chunk: publicRooms[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SearchItem extends StatelessWidget {
  final String title;
  final String colorSeed;
  final Uri? avatar;
  final void Function() onPressed;

  const _SearchItem({
    required this.title,
    required this.colorSeed,
    this.avatar,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: .min,
        children: [
          const SizedBox(height: 8),
          Avatar(mxContent: avatar, name: title, colorSeed: colorSeed),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
