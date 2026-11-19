// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:matrix/matrix.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';

typedef ScheduledSender =
    Future<void> Function(String roomId, Map<String, Object?> content);

class ScheduledRoomUnavailable implements Exception {
  const ScheduledRoomUnavailable();

  @override
  String toString() => 'ScheduledRoomUnavailable';
}

/// Sends the messages of this device's own schedule while the app runs.
///
/// A message is handed over at most once: its entry is stored as `sending`
/// before the send, so an app that dies mid-send never sends it a second time
/// (the entry comes back as `failed`). A message that is more than
/// [lateGrace] overdue is not sent by itself either: the user decides.
///
/// A round and a presence event work on a list they read earlier and wait for
/// the network between entries. Before an entry is sent or failed it is read
/// again from the store, atomically with every other write ([ScheduledStore.update]):
/// what was deleted, moved or sent meanwhile is left alone.
class ScheduledQueue {
  ScheduledQueue(
    this._store, {
    required ScheduledSender send,
    required DateTime Function() now,
    Stream<String>? onlineUsers,
    Future<bool> Function(String userId)? isOnline,
  }) : _send = send,
       _now = now,
       _onlineUsers = onlineUsers,
       _isOnline = isOnline;

  factory ScheduledQueue.forClient(
    Client client,
    ScheduledStore store, {
    DateTime Function()? now,
  }) => ScheduledQueue(
    store,
    send: (roomId, content) async {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        throw const ScheduledRoomUnavailable();
      }
      await room.sendEvent(Map<String, dynamic>.of(content));
    },
    now: now ?? DateTime.now,
    onlineUsers: client.onPresenceChanged.stream
        .where((p) => p.presence == PresenceType.online)
        .map((p) => p.userid),
    isOnline: (userId) async {
      try {
        final presence = await client.fetchCurrentPresence(userId);
        return presence.presence == PresenceType.online;
      } catch (_) {
        return false;
      }
    },
  );

  static const lateGrace = Duration(minutes: 10);
  static const maxTimerStep = Duration(minutes: 1);
  static const onlineMaxAge = Duration(days: 30);

  static final _queues = Expando<ScheduledQueue>('ScheduledQueue');

  static ScheduledQueue of(Client client) => _queues[client] ??=
      ScheduledQueue.forClient(client, ScheduledStore.of(client));

  static void forget(Client client) {
    _queues[client]?.stop();
    _queues[client] = null;
  }

  final ScheduledStore _store;
  final ScheduledSender _send;
  final DateTime Function() _now;
  final Stream<String>? _onlineUsers;
  final Future<bool> Function(String userId)? _isOnline;
  StreamSubscription<String>? _subscription;
  Timer? _timer;
  Future<void>? _running;
  var _again = false;
  var _stopped = false;

  Future<void> start() async {
    _stopped = false;
    await _store.ready;
    _subscription ??= _onlineUsers?.listen(
      (userId) => unawaited(_userCameOnline(userId)),
    );
    await evaluate();
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Looks at every entry once. Overlapping calls are merged into one more
  /// round.
  Future<void> evaluate() {
    if (_stopped) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _rounds().whenComplete(() => _running = null);
  }

  Future<void> _rounds() async {
    do {
      _again = false;
      await _round();
    } while (_again);
  }

  Future<void> _round() async {
    await _store.ready;
    final now = _now();
    DateTime? earliest;
    var waiting = false;
    for (final entry in _store.entries()) {
      if (entry.mode != ScheduledMode.device ||
          entry.state != ScheduledState.pending) {
        continue;
      }
      final at = entry.sendAt;
      if (at == null) {
        if (now.difference(entry.createdAt) > onlineMaxAge) {
          await _fail(entry, ScheduledState.pending, ScheduledFailure.expired);
          continue;
        }
        if (await _isOnline?.call(entry.untilOnline!) == true) {
          await _dispatch(entry);
          continue;
        }
        waiting = true;
        continue;
      }
      if (at.isAfter(now)) {
        waiting = true;
        if (earliest == null || at.isBefore(earliest)) earliest = at;
        continue;
      }
      if (now.difference(at) > lateGrace) {
        await _fail(entry, ScheduledState.pending, ScheduledFailure.late);
        continue;
      }
      await _dispatch(entry);
    }
    _arm(waiting, earliest, now);
  }

  void _arm(bool waiting, DateTime? earliest, DateTime now) {
    _timer?.cancel();
    _timer = null;
    if (_stopped || !waiting) return;
    final wait = earliest == null
        ? maxTimerStep
        : Duration(
            milliseconds: min(
              maxTimerStep.inMilliseconds,
              max(0, earliest.difference(now).inMilliseconds),
            ),
          );
    _timer = Timer(wait, () => unawaited(evaluate()));
  }

  Future<void> _userCameOnline(String userId) async {
    await _store.ready;
    final now = _now();
    for (final entry in _store.entries()) {
      if (entry.state != ScheduledState.pending ||
          entry.untilOnline != userId) {
        continue;
      }
      if (now.difference(entry.createdAt) > onlineMaxAge) {
        await _fail(entry, ScheduledState.pending, ScheduledFailure.expired);
        continue;
      }
      await _dispatch(entry);
    }
  }

  Future<void> sendNow(String id) async {
    await _store.ready;
    final entry = _store.entries().where((e) => e.id == id).firstOrNull;
    if (entry == null || entry.mode != ScheduledMode.device) return;
    await _dispatch(entry, manual: true);
  }

  /// Marks the entry failed, but only while it is still the [seen] one in
  /// state [from]: an entry deleted or moved meanwhile stays as it is.
  Future<void> _fail(
    ScheduledEntry seen,
    ScheduledState from,
    ScheduledFailure reason,
  ) async {
    try {
      await _store.update(
        seen.id,
        (current) => current.state == from && current.sendAt == seen.sendAt
            ? current.copyWith(state: ScheduledState.failed, reason: reason)
            : null,
      );
    } catch (e) {
      Logs().w('[Scheduled] could not mark an entry (${e.runtimeType})');
    }
  }

  /// Sends [seen] if the stored entry is still the one that was seen: pending
  /// at the same time. A manual send also takes a failed entry. Nothing is
  /// sent for an entry that is gone or already on its way.
  Future<void> _dispatch(ScheduledEntry seen, {bool manual = false}) async {
    if (_stopped) return;
    final ScheduledEntry? entry;
    try {
      entry = await _store.update(seen.id, (current) {
        if (current.state == ScheduledState.sending) return null;
        final unchanged =
            current.state == ScheduledState.pending &&
            current.sendAt == seen.sendAt;
        if (!manual && !unchanged) return null;
        return current.copyWith(state: ScheduledState.sending);
      });
    } catch (e) {
      Logs().w('[Scheduled] not sent, storage unavailable (${e.runtimeType})');
      return;
    }
    if (entry == null) return;
    try {
      await _send(entry.roomId, entry.content);
    } catch (e) {
      Logs().w('[Scheduled] send failed (${e.runtimeType})');
      await _fail(
        entry,
        ScheduledState.sending,
        e is ScheduledRoomUnavailable
            ? ScheduledFailure.roomUnavailable
            : ScheduledFailure.sendFailed,
      );
      return;
    }
    await _store.remove(entry.id);
  }
}
