// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/search/db_event_reader.dart';
import 'package:fluffychat/utils/search/index_policy.dart';
import 'package:fluffychat/utils/search/local_search.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:matrix/matrix.dart';

/// Filter-only searches ("files from Mara", no search word) cannot go to the
/// server, which needs a word. For unencrypted rooms they look at the events
/// the client already holds in its database: no request, nothing is stored.
class UnencryptedScan {
  UnencryptedScan(
    this._client, {
    StoredEventReader? reader,
    DateTime Function()? now,
  }) : _read =
           reader ?? ((room, limit) => readStoredEvents(_client, room, limit)),
       _now = now ?? DateTime.now;

  static const maxRooms = 20;
  static const perRoom = 200;

  final Client _client;
  final StoredEventReader _read;
  final DateTime Function() _now;

  Future<List<SearchHit>> run(
    MessageSearchFilter filter, {
    int limit = LocalSearch.defaultLimit,
  }) async {
    if (filter.isEmpty) return const [];
    final rooms =
        _client.rooms
            .where(
              (room) =>
                  room.membership == Membership.join &&
                  !room.encrypted &&
                  !room.isSpace &&
                  (filter.inRoomIds.isEmpty ||
                      filter.inRoomIds.contains(room.id)),
            )
            .toList()
          ..sort(
            (a, b) =>
                b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
          );
    final now = _now();
    final hits = <SearchHit>[];
    for (final candidate in rooms.take(maxRooms)) {
      final events = await _read(candidate, perRoom);
      final room = _client.getRoomById(candidate.id);
      if (room == null ||
          room.membership != Membership.join ||
          room.encrypted) {
        continue;
      }
      final policy = RetentionPolicy.forRoom(room);
      for (final event in events) {
        if (policy?.hides(event, now) == true) continue;
        final entry = IndexPolicy.describe(
          event,
          ownUserId: _client.userID ?? '',
          now: now,
        );
        if (entry == null || !filter.matches(entry, now)) continue;
        hits.add(SearchHit(entry, const []));
      }
    }
    hits.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return hits.take(limit).toList();
  }
}
