// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/search/db_event_reader.dart';
import 'package:fluffychat/utils/search/index_policy.dart';
import 'package:fluffychat/utils/search/message_index.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class CancelFlag {
  var cancelled = false;

  void cancel() => cancelled = true;
}

/// Feeds the [MessageIndex] of one account with the events the client already
/// holds decrypted: new timeline events, back-paginated history and, on
/// request, what the database has stored.
class IndexFeeder {
  IndexFeeder._(this._client, this._index, this._read);

  @visibleForTesting
  IndexFeeder.forTesting(
    Client client,
    MessageIndex index, {
    StoredEventReader? reader,
  }) : this._(
         client,
         index,
         reader ?? ((room, limit) => readStoredEvents(client, room, limit)),
       );

  static const yieldEvery = 50;

  static final _feeders = Expando<IndexFeeder>('IndexFeeder');

  static IndexFeeder of(Client client) => _feeders[client] ??= IndexFeeder._(
    client,
    MessageIndex.of(client),
    (room, limit) => readStoredEvents(client, room, limit),
  );

  static void forget(Client client) {
    unawaited(_feeders[client]?.stop());
    _feeders[client] = null;
  }

  final Client _client;
  final MessageIndex _index;
  final StoredEventReader _read;
  final _subscriptions = <StreamSubscription<Object?>>[];
  var _caughtUp = false;

  /// After the user wiped the index nothing is read back from the database
  /// until the next start.
  void markCaughtUp() => _caughtUp = true;

  @visibleForTesting
  bool get isCaughtUp => _caughtUp;

  @visibleForTesting
  set isCaughtUp(bool value) => _caughtUp = value;

  void start() {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(_client.onTimelineEvent.stream.listen(handle))
      ..add(_client.onHistoryEvent.stream.listen(handle))
      ..add(_client.onSync.stream.listen(_onSync));
  }

  Future<void> stop() async {
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    await Future.wait(subscriptions.map((s) => s.cancel()));
  }

  void _onSync(SyncUpdate sync) {
    final left = sync.rooms?.leave?.keys;
    if (left == null) return;
    for (final roomId in left) {
      _index.removeRoom(roomId);
    }
  }

  /// Applies one event. Never throws: events are untrusted input.
  void handle(Event event) {
    try {
      final roomId = event.room.id;
      final room = _client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) return;
      final redacted = IndexPolicy.redactionTarget(event);
      if (redacted != null) {
        _index.remove(roomId, redacted);
        return;
      }
      final edit = IndexPolicy.editOf(event);
      if (edit != null) {
        _index.applyEdit(
          roomId: roomId,
          targetId: edit.targetId,
          editorId: event.senderId,
          newText: edit.text,
          at: event.originServerTs.millisecondsSinceEpoch,
        );
        return;
      }
      final entry = IndexPolicy.fromEvent(
        event,
        ownUserId: _client.userID ?? '',
      );
      if (entry != null) _index.add(entry);
    } catch (_) {
      Logs().w('[Search] event skipped');
    }
  }

  /// Catches up once, after the first sync of this session has finished. A
  /// client that logs out first is left alone. Never throws.
  Future<void> catchUpAfterFirstSync() async {
    try {
      await _client.roomsLoading;
      if (_client.prevBatch == null && !await _firstSyncOrLogout()) return;
      await catchUp();
    } catch (_) {
      Logs().w('[Search] catch-up failed');
    }
  }

  /// True when the first sync finished, false when the client logged out.
  Future<bool> _firstSyncOrLogout() async {
    final result = Completer<bool>();
    final subscriptions = [
      _client.onSyncStatus.stream.listen((status) {
        if (status.status == SyncStatus.finished && !result.isCompleted) {
          result.complete(true);
        }
      }),
      _client.onLoginStateChanged.stream.listen((state) {
        if (state == LoginState.loggedOut && !result.isCompleted) {
          result.complete(false);
        }
      }),
    ];
    try {
      return await result.future;
    } finally {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    }
  }

  /// Reads what the database holds for the most recently active encrypted
  /// rooms and feeds it, oldest first so edits and redactions land after the
  /// message they belong to. Gives the event loop back every [yieldEvery]
  /// events. Returns how many events it looked at.
  Future<int> catchUp({
    int maxRooms = 100,
    int perRoom = 200,
    int maxEvents = 5000,
    CancelFlag? cancel,
  }) async {
    if (_caughtUp) return 0;
    final epoch = _index.epoch;
    bool stopped() => cancel?.cancelled == true || _index.epoch != epoch;
    final rooms =
        _client.rooms
            .where(
              (room) => room.membership == Membership.join && room.encrypted,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
          );
    var seen = 0;
    for (final candidate in rooms.take(maxRooms)) {
      if (stopped()) return seen;
      final events = await _read(candidate, perRoom);
      final room = _client.getRoomById(candidate.id);
      if (room == null || room.membership != Membership.join) continue;
      for (final event in events.reversed) {
        if (stopped() || seen >= maxEvents) return seen;
        handle(event);
        seen++;
        if (seen % yieldEvery == 0) await Future<void>.delayed(Duration.zero);
      }
    }
    if (!stopped()) _caughtUp = true;
    return seen;
  }
}
