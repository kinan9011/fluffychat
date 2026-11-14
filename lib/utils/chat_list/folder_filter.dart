// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

@immutable
class FolderContext {
  final SpaceTabsModel spaces;
  final bool hideRoomsInSpaces;

  const FolderContext({required this.spaces, this.hideRoomsInSpaces = false});
}

@immutable
class ChatListTabItem {
  final ChatListScope scope;
  final SpaceTab? space;

  const ChatListTabItem(this.scope, [this.space]);

  FolderRef get folder => scope.folder;
}

abstract class FolderFilter {
  static const builtInTabs = [
    FolderRef.unread,
    FolderRef.personal,
    FolderRef.groups,
  ];

  static bool matchesFolder(Room room, FolderRef ref) => switch (ref.kind) {
    FolderKind.all => true,
    FolderKind.unread => room.isUnreadOrInvited,
    FolderKind.personal => room.isDirectChat,
    FolderKind.groups => !room.isDirectChat,
    FolderKind.tag => room.tags.containsKey(ref.value),
    FolderKind.user => false,
  };

  static bool _keeps(Room room, ChatListScope scope, FolderContext ctx) {
    if (room.isJoinedSpace) return false;
    final spaceId = scope.spaceId;
    if (spaceId != null) {
      if (!(ctx.spaces.roomsBySpace[spaceId]?.contains(room.id) ?? false)) {
        return false;
      }
    }
    if (spaceId == null &&
        scope.folder.kind == FolderKind.all &&
        ctx.hideRoomsInSpaces &&
        ctx.spaces.roomsInAnySpace.contains(room.id)) {
      return false;
    }
    return matchesFolder(room, scope.folder);
  }

  static List<Room> apply(
    Iterable<Room> rooms,
    ChatListScope scope,
    FolderContext ctx,
  ) => rooms.where((room) => _keeps(room, scope, ctx)).toList();

  static int unreadCount(
    Iterable<Room> unreadRooms,
    ChatListScope scope,
    FolderContext ctx,
  ) => unreadRooms.where((room) => _keeps(room, scope, ctx)).length;

  static List<ChatListTabItem> tabs({
    required SpaceNavigationMode mode,
    required List<SpaceTab> spaces,
    required List<String> tags,
    required bool showFoldersAfterSpaces,
    String? currentSpaceId,
  }) {
    ChatListTabItem folderTab(FolderRef ref, String? spaceId) =>
        ChatListTabItem(ChatListScope(spaceId: spaceId, folder: ref));
    List<ChatListTabItem> folderTabs(String? spaceId) => [
      for (final ref in builtInTabs) folderTab(ref, spaceId),
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
