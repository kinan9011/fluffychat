// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fluffychat/utils/logged_in_database.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:fluffychat/utils/scheduling/scheduled_content.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

enum ScheduledMode { device, server }

enum ScheduledState { pending, sending, failed }

/// Why an entry is `failed`: the list says what really happened.
enum ScheduledFailure {
  late,
  sendFailed,
  roomUnavailable,
  rescheduleFailed,
  expired,
}

class ScheduledCapReached implements Exception {
  const ScheduledCapReached();

  @override
  String toString() => 'ScheduledCapReached';
}

class ScheduledStorageUnavailable implements Exception {
  const ScheduledStorageUnavailable();

  @override
  String toString() => 'ScheduledStorageUnavailable';
}

/// One message waiting to be sent, by this device or by the homeserver.
@immutable
class ScheduledEntry {
  const ScheduledEntry({
    required this.id,
    required this.roomId,
    required this.mode,
    required this.createdAt,
    required this.content,
    this.sendAt,
    this.untilOnline,
    this.delayId,
    this.state = ScheduledState.pending,
    this.reason,
    this.encrypted = false,
  });

  static final _id = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
  static final _delayId = RegExp(r'^[A-Za-z0-9_.~=+-]{1,255}$');
  static final _dots = RegExp(r'^\.+$');
  static const _maxEpochMs = 4102444800000;

  final String id;
  final String roomId;
  final ScheduledMode mode;
  final DateTime? sendAt;
  final String? untilOnline;
  final DateTime createdAt;
  final String? delayId;
  final ScheduledState state;
  final ScheduledFailure? reason;

  /// The room was encrypted when the server was asked to hold this message.
  final bool encrypted;
  final Map<String, Object?> content;

  static String newId() {
    final random = Random.secure();
    return base64Url.encode([for (var i = 0; i < 12; i++) random.nextInt(256)]);
  }

  /// Delay ids end up in a URL path: only unreserved characters, never a
  /// path segment of dots.
  static bool isDelayId(Object? value) =>
      value is String && _delayId.hasMatch(value) && !_dots.hasMatch(value);

  ScheduledEntry copyWith({
    DateTime? sendAt,
    ScheduledState? state,
    String? delayId,
    ScheduledFailure? reason,
  }) {
    final next = state ?? this.state;
    return ScheduledEntry(
      id: id,
      roomId: roomId,
      mode: mode,
      createdAt: createdAt,
      content: content,
      sendAt: sendAt ?? this.sendAt,
      untilOnline: untilOnline,
      delayId: delayId ?? this.delayId,
      state: next,
      reason: next == ScheduledState.failed ? reason ?? this.reason : null,
      encrypted: encrypted,
    );
  }

  /// What is left of an entry the server no longer holds: the text stays on
  /// this device, to send now, reschedule or delete.
  ScheduledEntry asFailedDevice() => ScheduledEntry(
    id: id,
    roomId: roomId,
    mode: ScheduledMode.device,
    createdAt: createdAt,
    content: content,
    sendAt: sendAt,
    untilOnline: untilOnline,
    state: ScheduledState.failed,
    reason: ScheduledFailure.rescheduleFailed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'room': roomId,
    'mode': mode.name,
    'at': sendAt?.millisecondsSinceEpoch,
    'online': untilOnline,
    'created': createdAt.millisecondsSinceEpoch,
    'delay': delayId,
    'state': state.name,
    'reason': reason?.name,
    'encrypted': encrypted,
    'content': content,
  };

  /// The entry for [json], or null when anything about it is off. With
  /// [recoverSending] (reading the stored document) a state of `sending`
  /// means the app died mid-send: it comes back as `failed` and is never sent
  /// again by itself.
  static ScheduledEntry? fromJson(
    Object? json,
    DateTime now, {
    bool recoverSending = false,
  }) {
    if (json is! Map) return null;
    final id = json['id'];
    final room = json['room'];
    if (id is! String || !_id.hasMatch(id)) return null;
    if (room is! String || !isMatrixRoomId(room)) return null;
    final mode = ScheduledMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    final state = ScheduledState.values
        .where((s) => s.name == json['state'])
        .firstOrNull;
    if (mode == null || state == null) return null;
    final created = _time(json['created']);
    if (created == null) return null;
    final at = json['at'];
    final sendAt = at == null ? null : _time(at);
    if (at != null && sendAt == null) return null;
    final online = json['online'];
    if (online != null &&
        (online is! String ||
            !online.startsWith('@') ||
            !online.isValidMatrixIdStrict())) {
      return null;
    }
    if ((sendAt == null) == (online == null)) return null;
    if (sendAt != null &&
        (sendAt.isBefore(created.subtract(const Duration(days: 1))) ||
            sendAt.isAfter(now.add(const Duration(days: 366))))) {
      return null;
    }
    final delay = json['delay'];
    if (mode == ScheduledMode.server) {
      if (!isDelayId(delay) || sendAt == null) return null;
    } else if (delay != null || online != null && sendAt != null) {
      return null;
    }
    final encrypted = json['encrypted'] ?? false;
    if (encrypted is! bool) return null;
    final content = ScheduledContent.validate(json['content']);
    if (content == null) return null;
    final recovered = recoverSending && state == ScheduledState.sending;
    final failed = recovered || state == ScheduledState.failed;
    return ScheduledEntry(
      id: id,
      roomId: room,
      mode: mode,
      createdAt: created,
      content: content,
      sendAt: sendAt,
      untilOnline: online as String?,
      delayId: delay as String?,
      state: recovered ? ScheduledState.failed : state,
      reason: failed
          ? ScheduledFailure.values
                    .where((r) => r.name == json['reason'])
                    .firstOrNull ??
                ScheduledFailure.sendFailed
          : null,
      encrypted: encrypted,
    );
  }

  static DateTime? _time(Object? value) {
    if (value is! int || value < 0 || value > _maxEpochMs) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}

/// Messages waiting to be sent, one document per account inside that
/// account's database (encrypted on native platforms, plain on the web or
/// without a keyring, which the app warns about). Nothing goes to the shared
/// preferences and nothing is logged except constant strings.
class ScheduledStore {
  ScheduledStore._(this._database, this._now) {
    ready = _load();
  }

  @visibleForTesting
  ScheduledStore.forTesting(
    DatabaseApi Function() database, {
    DateTime Function()? now,
  }) : this._(database, now ?? DateTime.now);

  static const documentKey = 'im.fluffychat.scheduled.v1';
  static const maxEntries = 100;
  static const maxDocumentBytes = 4 * 1024 * 1024;

  static final _stores = Expando<ScheduledStore>('ScheduledStore');
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static ScheduledStore of(Client client) {
    final existing = _stores[client];
    if (existing != null) return existing;
    final store = ScheduledStore._(
      () => loggedInDatabase(client),
      DateTime.now,
    );
    // The SDK wipes its custom cache objects with `clearCache()`: write the
    // entries again so a cleared cache does not silently drop them.
    client.onCacheCleared.stream.listen(
      (_) => unawaited(store.ready.then((_) => store._rewrite())),
    );
    return _stores[client] = store;
  }

  static void forget(Client client) => _stores[client] = null;

  final DatabaseApi Function() _database;
  final DateTime Function() _now;
  final _entries = <String, ScheduledEntry>{};
  var _loadFailed = false;
  Future<void> _serial = Future.value();

  /// Completes when the stored entries are loaded. Never throws.
  late final Future<void> ready;

  Future<void> _load() => _loadDocument();

  Future<void> _loadDocument() async {
    try {
      final cached = await _database().getCustomCacheObject(documentKey);
      _loadFailed = false;
      _entries
        ..clear()
        ..addAll(_parse(cached?.content));
      if (_entries.isNotEmpty) revision.value++;
    } catch (_) {
      _loadFailed = true;
      Logs().w('[Scheduled] storage unavailable');
    }
  }

  Map<String, ScheduledEntry> _parse(Object? document) {
    if (document is! Map || document['v'] != 1) return {};
    final list = document['entries'];
    if (list is! List) return {};
    final now = _now();
    final parsed = <ScheduledEntry>[];
    for (final item in list) {
      final entry = ScheduledEntry.fromJson(item, now, recoverSending: true);
      if (entry != null) parsed.add(entry);
    }
    parsed.sort(_byTime);
    return {for (final e in parsed.take(maxEntries)) e.id: e};
  }

  static int _byTime(ScheduledEntry a, ScheduledEntry b) {
    final left = a.sendAt;
    final right = b.sendAt;
    if (left == null || right == null) {
      return left == right ? 0 : (left == null ? -1 : 1);
    }
    return left.compareTo(right);
  }

  /// Messages the homeserver still holds and will send, which stay there when
  /// this device logs out.
  int get serverHeldCount => entries()
      .where(
        (entry) =>
            entry.delayId != null && entry.state == ScheduledState.pending,
      )
      .length;

  /// When online first, then by time.
  List<ScheduledEntry> entries({String? roomId}) => [
    for (final e in _entries.values)
      if (roomId == null || e.roomId == roomId) e,
  ]..sort(_byTime);

  ScheduledEntry? byDelayId(String delayId) =>
      _entries.values.where((e) => e.delayId == delayId).firstOrNull;

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Map<String, Object?> _document() => {
    'v': 1,
    'entries': [for (final e in entries()) e.toJson()],
  };

  /// A document that could not be read is never overwritten: it is read again
  /// first and nothing is written while it stays unreadable.
  Future<void> _ensureReadable() async {
    if (_loadFailed) await _loadDocument();
    if (_loadFailed) throw const ScheduledStorageUnavailable();
  }

  Future<bool> _persist() async {
    try {
      await _database().cacheCustomObject(documentKey, _document());
      return true;
    } catch (_) {
      Logs().w('[Scheduled] storage unavailable');
      return false;
    }
  }

  Future<void> _rewrite() => _exclusive(() async {
    if (_loadFailed) return;
    await _persist();
  });

  /// Adds or replaces an entry. Throws [ScheduledCapReached] over the caps and
  /// [ScheduledStorageUnavailable] when the database cannot keep it: the
  /// caller must tell the user, a message that is not stored is not scheduled.
  Future<void> put(ScheduledEntry entry) async {
    final checked = ScheduledEntry.fromJson(entry.toJson(), _now());
    if (checked == null) throw ArgumentError('entry');
    await ready;
    await _exclusive(() async {
      await _ensureReadable();
      await _commit(checked);
    });
    revision.value++;
  }

  /// Replaces the stored entry [id] by what [change] makes of it, atomically
  /// with every other write: [change] sees the entry as it is when this turn
  /// comes, after earlier removals and updates. Returns the stored entry, or
  /// null when it is gone or [change] answers null. Same errors as [put].
  Future<ScheduledEntry?> update(
    String id,
    ScheduledEntry? Function(ScheduledEntry current) change,
  ) async {
    await ready;
    final changed = await _exclusive(() async {
      await _ensureReadable();
      final current = _entries[id];
      if (current == null) return null;
      final next = change(current);
      if (next == null) return null;
      final checked = ScheduledEntry.fromJson(next.toJson(), _now());
      if (checked == null || checked.id != id) throw ArgumentError('entry');
      await _commit(checked);
      return checked;
    });
    if (changed != null) revision.value++;
    return changed;
  }

  Future<void> _commit(ScheduledEntry checked) async {
    final previous = _entries[checked.id];
    if (previous == null && _entries.length >= maxEntries) {
      throw const ScheduledCapReached();
    }
    _entries[checked.id] = checked;
    void rollback() {
      if (previous == null) {
        _entries.remove(checked.id);
        return;
      }
      _entries[checked.id] = previous;
    }

    if (utf8.encode(jsonEncode(_document())).length > maxDocumentBytes) {
      rollback();
      throw const ScheduledCapReached();
    }
    if (!await _persist()) {
      rollback();
      throw const ScheduledStorageUnavailable();
    }
  }

  Future<void> remove(String id) async {
    await ready;
    await _exclusive(() async {
      if (_loadFailed) await _loadDocument();
      if (_entries.remove(id) == null) return;
      await _persist();
    });
    revision.value++;
  }

  @visibleForTesting
  Future<void> flush() => _serial;
}
