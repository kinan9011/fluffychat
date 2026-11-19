// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat_list/folder_ref.dart';
import 'package:odango/utils/chat_list/folder_store.dart';
import 'package:odango/utils/chat_list/space_tabs_model.dart';
import 'package:odango/utils/matrix_sdk_extensions/chat_list_room_extension.dart';

@immutable
class FolderContext {
  final SpaceTabsModel spaces;
  final List<UserFolder> userFolders;
  final bool hideRoomsInSpaces;

  const FolderContext({
    required this.spaces,
    this.userFolders = const [],
    this.hideRoomsInSpaces = false,
  });
}

@immutable
class ChatListTabItem {
  final ChatListScope scope;
  final SpaceTab? space;
  final String? label;

  const ChatListTabItem(this.scope, [this.space, this.label]);

  FolderRef get folder => scope.folder;
}

abstract class FolderFilter {
  static const builtInTabs = [
    FolderRef.unread,
    FolderRef.personal,
    FolderRef.groups,
  ];

  static bool matchesFolder(Room room, FolderRef ref, FolderContext ctx) =>
      switch (ref.kind) {
        FolderKind.all => true,
        FolderKind.unread => room.isUnreadOrInvited,
        FolderKind.personal => room.isDirectChat,
        FolderKind.groups => !room.isDirectChat,
        FolderKind.tag => room.tags.containsKey(ref.value),
        FolderKind.user => ctx.userFolders.any(
          (f) => f.id == ref.value && f.matches(room),
        ),
      };

  static bool _keeps(Room room, ChatListScope scope, FolderContext ctx) {
    if (room.isJoinedSpace) return false;
    if (scope.archived != room.isArchivedChat) return false;
    final spaceId = scope.spaceId;
    if (spaceId != null) {
      if (!(ctx.spaces.roomsBySpace[spaceId]?.contains(room.id) ?? false)) {
        return false;
      }
    }
    if (!scope.archived &&
        spaceId == null &&
        scope.folder.kind == FolderKind.all &&
        ctx.hideRoomsInSpaces &&
        ctx.spaces.roomsInAnySpace.contains(room.id)) {
      return false;
    }
    return matchesFolder(room, scope.folder, ctx);
  }

  static List<Room> apply(
    Iterable<Room> rooms,
    ChatListScope scope,
    FolderContext ctx,
  ) => _pinOrdered(rooms.where((room) => _keeps(room, scope, ctx)).toList());

  static List<Room> _pinOrdered(List<Room> rooms) {
    final start = rooms.indexWhere((room) => room.isFavourite);
    if (start < 0) return rooms;
    var end = start;
    while (end < rooms.length && rooms[end].isFavourite) {
      end++;
    }
    final pinned = rooms.sublist(start, end).indexed.toList()
      ..sort((a, b) {
        final byOrder = (a.$2.pinOrder ?? double.infinity).compareTo(
          b.$2.pinOrder ?? double.infinity,
        );
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [
      ...rooms.take(start),
      ...pinned.map((entry) => entry.$2),
      ...rooms.skip(end),
    ];
  }

  static int unreadCount(
    Iterable<Room> unreadRooms,
    ChatListScope scope,
    FolderContext ctx,
  ) => unreadRooms.where((room) => _keeps(room, scope, ctx)).length;

  static List<ChatListTabItem> tabs({
    required SpaceNavigationMode mode,
    required List<SpaceTab> spaces,
    required List<String> tags,
    List<UserFolder> userFolders = const [],
    required bool showFoldersAfterSpaces,
    String? currentSpaceId,
  }) {
    ChatListTabItem folderTab(
      FolderRef ref,
      String? spaceId, [
      String? label,
    ]) => ChatListTabItem(
      ChatListScope(spaceId: spaceId, folder: ref),
      null,
      label,
    );
    List<ChatListTabItem> folderTabs(String? spaceId) => [
      for (final ref in builtInTabs) folderTab(ref, spaceId),
      for (final folder in userFolders)
        folderTab(FolderRef(FolderKind.user, folder.id), spaceId, folder.name),
      for (final tag in tags)
        folderTab(FolderRef(FolderKind.tag, tag), spaceId),
    ];

    if (mode == SpaceNavigationMode.switcher) {
      return [
        folderTab(FolderRef.all, currentSpaceId),
        ...folderTabs(currentSpaceId),
      ];
    }
    return [
      folderTab(FolderRef.all, null),
      for (final space in spaces)
        ChatListTabItem(ChatListScope(spaceId: space.spaceId), space),
      if (showFoldersAfterSpaces || spaces.isEmpty) ...folderTabs(null),
    ];
  }
}
