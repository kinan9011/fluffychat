// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bounded_matrix_request.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/search/index_policy.dart';
import 'package:fluffychat/utils/search/local_search.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/utils/search/search_query.dart';
import 'package:matrix/matrix.dart';

typedef SearchApi =
    Future<SearchResults> Function(Categories categories, {String? nextBatch});

class ServerSearchPage {
  const ServerSearchPage(this.hits, this.nextBatch);

  static const empty = ServerSearchPage([], null);

  final List<SearchHit> hits;
  final String? nextBatch;
}

/// Server side search of the user's own homeserver, for joined rooms that are
/// not encrypted only. The response is untrusted: whatever was not asked for,
/// is not a plain message of such a room, is hidden by the retention timer or
/// does not pass the filter is dropped.
class ServerSearch {
  ServerSearch(this._client, {SearchApi? api, DateTime Function()? now})
    : _api = api ?? _boundedSearch(_client),
      _now = now ?? DateTime.now;

  static const maxResponseBytes = 4 * 1024 * 1024;

  static SearchApi _boundedSearch(Client client) =>
      (categories, {nextBatch}) async => SearchResults.fromJson(
        await boundedMatrixJson(
          client,
          'POST',
          '_matrix/client/v3/search',
          maxBytes: maxResponseBytes,
          query: {'next_batch': ?nextBatch},
          body: {'search_categories': categories.toJson()},
        ),
      );

  static const maxRooms = 200;
  static const pageSize = 20;
  static const maxPages = 5;
  static const maxResults = 100;
  static const maxNextBatchChars = 512;

  final Client _client;
  final SearchApi _api;
  final DateTime Function() _now;

  /// Joined, unencrypted rooms, the most recently active first.
  List<Room> eligibleRooms() {
    final rooms =
        _client.rooms
            .where(
              (room) =>
                  room.membership == Membership.join &&
                  !room.encrypted &&
                  !room.isSpace,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
          );
    return rooms.take(maxRooms).toList();
  }

  static bool _mediaOnly(Set<SearchType> types) =>
      types.isNotEmpty &&
      types.every(
        (type) => const {
          SearchType.photos,
          SearchType.videos,
          SearchType.files,
          SearchType.voice,
        }.contains(type),
      );

  /// One page of results. Sends nothing when there is no search word or no
  /// room the server could search.
  Future<ServerSearchPage> search(
    SearchQuery query,
    MessageSearchFilter filter, {
    String? nextBatch,
    int page = 0,
  }) async {
    if (query.isEmpty || page >= maxPages) return ServerSearchPage.empty;
    final eligible = eligibleRooms()
        .where(
          (room) =>
              filter.inRoomIds.isEmpty || filter.inRoomIds.contains(room.id),
        )
        .toList();
    if (eligible.isEmpty) return ServerSearchPage.empty;
    final requested = {for (final room in eligible) room.id};
    final response = await _api(
      Categories(
        roomEvents: RoomEventsCriteria(
          searchTerm: query.text,
          keys: [KeyKind.contentBody],
          orderBy: SearchOrder.recent,
          filter: SearchFilter(
            limit: pageSize,
            rooms: requested.toList(),
            senders: filter.fromIds.isEmpty ? null : filter.fromIds.toList(),
            containsUrl: _mediaOnly(filter.types) ? true : null,
          ),
        ),
      ),
      nextBatch: nextBatch,
    );
    final result = response.searchCategories.roomEvents;
    final now = _now();
    final hits = <SearchHit>[];
    for (final item in result?.results ?? const <Result>[]) {
      final hit = _accept(item.result, requested, query, filter, now);
      if (hit != null) hits.add(hit);
      if (hits.length >= pageSize) break;
    }
    final token = result?.nextBatch;
    return ServerSearchPage(
      hits,
      token == null || token.isEmpty || token.length > maxNextBatchChars
          ? null
          : token,
    );
  }

  SearchHit? _accept(
    MatrixEvent? matrixEvent,
    Set<String> requested,
    SearchQuery query,
    MessageSearchFilter filter,
    DateTime now,
  ) {
    if (matrixEvent == null) return null;
    final roomId = matrixEvent.roomId;
    if (roomId == null || !requested.contains(roomId)) return null;
    final room = _client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join || room.encrypted) {
      return null;
    }
    final Event event;
    try {
      event = Event.fromMatrixEvent(matrixEvent, room);
    } catch (_) {
      return null;
    }
    if (RetentionPolicy.forRoom(room)?.hides(event, now) == true) return null;
    final entry = IndexPolicy.describe(
      event,
      ownUserId: _client.userID ?? '',
      now: now,
    );
    if (entry == null || !filter.matches(entry, now)) return null;
    return SearchHit(entry, LocalSearch.highlights(entry.text, query));
  }
}
