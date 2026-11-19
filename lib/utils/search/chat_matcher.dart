// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:odango/utils/search/search_query.dart';

class ChatMatch {
  const ChatMatch(this.room, {required this.archived});

  final Room room;
  final bool archived;
}

/// The chats whose name or alias contain every search word. With no search
/// word it is the most recently active chats.
abstract final class ChatMatcher {
  static const defaultLimit = 30;

  static List<ChatMatch> run(
    Iterable<Room> rooms,
    SearchQuery query, {
    required String Function(Room room) nameOf,
    int limit = defaultLimit,
  }) {
    final joined =
        rooms.where((room) => room.membership == Membership.join).toList()
          ..sort(
            (a, b) =>
                b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
          );
    final matches = <ChatMatch>[];
    for (final room in joined) {
      if (matches.length >= limit) break;
      if (!_matches(room, query, nameOf)) continue;
      matches.add(ChatMatch(room, archived: room.isArchivedChat));
    }
    return matches;
  }

  static bool _matches(
    Room room,
    SearchQuery query,
    String Function(Room) nameOf,
  ) {
    if (query.isEmpty) return true;
    final haystack = '${nameOf(room)}\n${room.canonicalAlias}'.toLowerCase();
    return query.terms.every(haystack.contains);
  }
}
