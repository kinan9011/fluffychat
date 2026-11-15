// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

@immutable
class SpaceTab {
  final String spaceId;
  final String name;
  final Uri? avatar;
  final int unread;

  const SpaceTab({
    required this.spaceId,
    required this.name,
    required this.avatar,
    required this.unread,
  });
}

/// Top-level joined spaces as tabs and the rooms below each of them. The
/// hierarchy comes from untrusted state events, so every walk is bounded and
/// one huge space cannot starve the others.
class SpaceTabsModel {
  static const maxDepth = 8;
  static const maxVisited = 10000;

  final List<SpaceTab> tabs;
  final Map<String, Set<String>> roomsBySpace;
  final Set<String> roomsInAnySpace;

  const SpaceTabsModel._(this.tabs, this.roomsBySpace, this.roomsInAnySpace);

  static const empty = SpaceTabsModel._([], {}, {});

  factory SpaceTabsModel.build(
    Iterable<Room> rooms, {
    required String Function(Room) nameOf,
  }) {
    final byId = {for (final room in rooms) room.id: room};
    final joinedSpaces = rooms.where((room) => room.isJoinedSpace).toList();
    if (joinedSpaces.isEmpty) return empty;

    final children = {
      for (final space in joinedSpaces)
        space.id: space.spaceChildren
            .map((child) => child.roomId)
            .nonNulls
            .toList(),
    };
    final childOfAnother = {
      for (final entry in children.entries)
        for (final id in entry.value)
          if (id != entry.key) id,
    };
    final topLevel = joinedSpaces
        .where((space) => !childOfAnother.contains(space.id))
        .toList();

    Set<String> spacesBelow(String rootId) {
      final seen = <String>{};
      final stack = [rootId];
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        if (!seen.add(id)) continue;
        stack.addAll(children[id]!.where(children.containsKey));
      }
      return seen;
    }

    final roomsBySpace = <String, Set<String>>{};
    var truncated = false;

    void walk(Room root) {
      final members = roomsBySpace[root.id] = {};
      var visits = 0;
      final seen = {root.id};
      final stack = [(root.id, 0)];
      while (stack.isNotEmpty) {
        final (space, depth) = stack.removeLast();
        for (final id in children[space]!) {
          if (++visits > maxVisited) {
            truncated = true;
            return;
          }
          if (children.containsKey(id)) {
            if (depth < maxDepth && seen.add(id)) stack.add((id, depth + 1));
            continue;
          }
          members.add(id);
        }
      }
    }

    topLevel.forEach(walk);
    final reached = {for (final space in topLevel) ...spacesBelow(space.id)};
    final orphans = joinedSpaces
        .where((space) => !reached.contains(space.id))
        .toList();
    final orphanReach = {
      for (final space in orphans) space.id: spacesBelow(space.id),
    };
    final orphanTabs = orphans.where((space) {
      final hiddenBelowAnother = orphans.any(
        (other) =>
            other != space &&
            orphanReach[other.id]!.contains(space.id) &&
            !orphanReach[space.id]!.contains(other.id),
      );
      if (!hiddenBelowAnother) walk(space);
      return !hiddenBelowAnother;
    }).toList();
    if (truncated) Logs().w('[SpaceTabs] hierarchy truncated');
    final tops = [...topLevel, ...orphanTabs];

    final tabs = [
      for (final space in tops)
        SpaceTab(
          spaceId: space.id,
          name: nameOf(space),
          avatar: space.avatar,
          unread: (roomsBySpace[space.id] ?? const <String>{}).where((id) {
            final room = byId[id];
            return room != null &&
                room.isUnreadOrInvited &&
                !room.isArchivedChat;
          }).length,
        ),
    ]..sort(_compareTabs);

    return SpaceTabsModel._(tabs, roomsBySpace, {
      for (final members in roomsBySpace.values) ...members,
    });
  }

  static int _compareTabs(SpaceTab a, SpaceTab b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.spaceId.compareTo(b.spaceId);
  }
}
