// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:odango/utils/topics/topic.dart';

class TopicsLoadFailed implements Exception {
  const TopicsLoadFailed();

  @override
  String toString() => 'TopicsLoadFailed';
}

typedef ThreadRootsFetch =
    Future<GetThreadRootsResponse> Function(String roomId, {String? from});

typedef EventDecrypt = Future<Event> Function(Event event);

/// Loads the topics of a room: thread roots from the server (bounded: pages,
/// entries per page, total), titles from the root events. The result lives
/// in memory only; titles of encrypted rooms are never stored.
class TopicLoader {
  TopicLoader(
    this.room, {
    ThreadRootsFetch? fetch,
    EventDecrypt? decrypt,
    DateTime Function()? now,
    this.minInterval = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 1),
  }) : _fetch = fetch ?? _defaultFetch(room),
       _decrypt = decrypt ?? _defaultDecrypt(room),
       _now = now ?? DateTime.now;

  final Room room;
  final Duration minInterval;
  final Duration maxBackoff;
  final ThreadRootsFetch _fetch;
  final EventDecrypt _decrypt;
  final DateTime Function() _now;

  List<Topic> _cache = const [];
  DateTime? _loadedAt;
  DateTime? _failedAt;
  var _failures = 0;
  Future<List<Topic>>? _inFlight;

  List<Topic> get cached => _cache;

  static ThreadRootsFetch _defaultFetch(Room room) =>
      (roomId, {from}) => room.client.getThreadRoots(
        roomId,
        include: Include.all,
        limit: 50,
        from: from,
      );

  static EventDecrypt _defaultDecrypt(Room room) =>
      (event) async =>
          await room.client.encryption?.decryptRoomEvent(event) ?? event;

  Duration get _backoff {
    final wait = minInterval * (1 << (_failures - 1).clamp(0, 10));
    return wait > maxBackoff ? maxBackoff : wait;
  }

  /// Throws [TopicsLoadFailed]. Asking again within [minInterval] returns
  /// the last result without a request; after a failure the wait grows from
  /// [minInterval] to [maxBackoff] and the failure is reported again. Only
  /// [force] (an explicit retry by the user) skips the wait.
  Future<List<Topic>> load({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    if (!force) {
      final failedAt = _failedAt;
      if (failedAt != null && _now().difference(failedAt) < _backoff) {
        return Future.error(const TopicsLoadFailed());
      }
      final at = _loadedAt;
      if (failedAt == null &&
          at != null &&
          _now().difference(at) < minInterval) {
        return Future.value(_cache);
      }
    }
    return _inFlight = _run().whenComplete(() => _inFlight = null);
  }

  Future<List<Topic>> _run() async {
    final roomId = room.id;
    final topics = <String, Topic>{};
    try {
      String? from;
      for (var page = 0; page < TopicParser.maxPages; page++) {
        final response = await _fetch(roomId, from: from);
        for (final raw in response.chunk.take(TopicParser.maxRootsPerPage)) {
          if (topics.length >= TopicParser.maxTopics) break;
          final topic = await _topic(raw);
          if (topic != null) topics.putIfAbsent(topic.rootEventId, () => topic);
        }
        from = response.nextBatch;
        if (from == null || topics.length >= TopicParser.maxTopics) break;
      }
    } catch (_) {
      Logs().w('[Topics] could not load the topics');
      _failures++;
      _failedAt = _now();
      throw const TopicsLoadFailed();
    }
    final sorted = topics.values.toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    _loadedAt = _now();
    _failedAt = null;
    _failures = 0;
    return _cache = List.unmodifiable(sorted);
  }

  Future<Topic?> _topic(MatrixEvent raw) async {
    try {
      var event = Event.fromMatrixEvent(raw, room);
      if (event.type == EventTypes.Encrypted) {
        try {
          event = await _decrypt(event);
        } catch (_) {
          Logs().w('[Topics] a thread root could not be decrypted');
        }
      }
      return TopicParser.fromRoot(
        eventId: raw.eventId,
        content: event.type == EventTypes.Encrypted ? const {} : event.content,
        timestamp: raw.originServerTs,
        unsigned: raw.unsigned,
        displayName: (userId) =>
            room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Adds the roots found in the loaded timeline (a topic without replies is
  /// not listed by the server) and sorts the result.
  static List<Topic> mergeTimelineRoots(
    List<Topic> topics,
    Iterable<Event> timelineEvents,
  ) {
    final byId = {for (final topic in topics) topic.rootEventId: topic};
    for (final event in timelineEvents) {
      if (byId.length >= TopicParser.maxTopics) break;
      if (byId.containsKey(event.eventId)) continue;
      if (event.type != EventTypes.Message) continue;
      if (event.content[topicContentKey] is! Map) continue;
      final topic = TopicParser.fromRoot(
        eventId: event.eventId,
        content: event.content,
        timestamp: event.originServerTs,
      );
      if (topic != null) byId[topic.rootEventId] = topic;
    }
    return byId.values.toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }
}
