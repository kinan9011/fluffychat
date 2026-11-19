// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';

/// Unread mentions of the own user in the loaded timeline, and which of them
/// the user already jumped to. Sends nothing.
class MentionJump {
  final Set<String> _visited = {};
  int _loadedRounds = 0;
  int _extraScan = 0;
  bool _exhausted = false;

  /// Bumps whenever something that changes the result of [pending] changes.
  int revision = 0;

  /// True once a search for older mentions ended without a hit and nothing
  /// more is to be loaded (or the budget is spent). The server count is not
  /// trusted from then on, so the button cannot stay up as a dead end.
  bool get exhausted => _exhausted;

  /// Oldest-first ids of unread mentions. [eventsNewestFirst] is the visible
  /// timeline; the scan is capped because senders control the event count.
  List<String> pending({
    required Iterable<Event> eventsNewestFirst,
    required String? ownUserId,
    required String? fullyReadEventId,
    required bool Function(Event) isHighlight,
    int maxScan = AppChat.maxMentionScan,
  }) {
    if (ownUserId == null) return [];
    final found = <String>[];
    for (final event in eventsNewestFirst.take(maxScan + _extraScan)) {
      if (event.eventId == fullyReadEventId) break;
      if (event.senderId == ownUserId || event.redacted) continue;
      if (_visited.contains(event.eventId)) continue;
      if (isHighlight(event) || event.mentions.userIds.contains(ownUserId)) {
        found.add(event.eventId);
      }
    }
    return found.reversed.toList();
  }

  int get visitedCount => _visited.length;

  /// What the badge shows: the mentions found locally, plus the ones the
  /// server counts that are not loaded yet, until a search came up empty.
  int countFor({required int localPending, required int serverCount}) =>
      _exhausted
      ? localPending
      : math.max(localPending, math.max(0, serverCount - _visited.length));

  String? next(List<String> pending) =>
      pending.firstWhereOrNull((id) => !_visited.contains(id));

  /// The id to jump to. While no unread mention is loaded, [loadMore] pulls in
  /// older history, at most [maxRounds] times per call and [maxTotalRounds]
  /// until [rearm], and only while [canLoadMore]. Every loaded round widens
  /// the scan by [scanPerRound] events.
  Future<String?> nextLoading({
    required List<String> Function() pending,
    required bool Function() canLoadMore,
    required Future<void> Function() loadMore,
    int maxRounds = 5,
    int maxTotalRounds = 20,
    int scanPerRound = 100,
  }) async {
    var id = next(pending());
    for (
      var round = 0;
      id == null &&
          round < maxRounds &&
          _loadedRounds < maxTotalRounds &&
          canLoadMore();
      round++
    ) {
      await loadMore();
      _loadedRounds++;
      _extraScan += scanPerRound;
      revision++;
      id = next(pending());
    }
    if (id == null && (_loadedRounds >= maxTotalRounds || !canLoadMore())) {
      _exhausted = true;
      revision++;
    }
    return id;
  }

  void visit(String id) {
    _visited.add(id);
    revision++;
  }

  /// A new unread state: forget what was visited and searched.
  void reset() {
    _visited.clear();
    rearm();
  }

  /// The server count changed: search again.
  void rearm() {
    _exhausted = false;
    _loadedRounds = 0;
    revision++;
  }
}
