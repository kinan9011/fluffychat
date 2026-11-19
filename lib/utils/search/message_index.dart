// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';
import 'package:odango/utils/matrix_room_id.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:odango/utils/retention/retention_policy.dart';
import 'package:odango/utils/search/index_policy.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/search_kind.dart';

/// Plaintext of encrypted rooms for global search, one document per account
/// inside that account's encrypted database. Nothing is written to the shared
/// preferences or to files and nothing is logged except constant strings.
/// Where the database is not encrypted (web, key store failure) the index only
/// lives in memory.
class MessageIndex {
  MessageIndex._(
    this._database,
    this._canPersist,
    this._persistDelay, {
    RetentionPolicy? Function(String roomId)? retentionOf,
    DateTime Function()? now,
  }) : _retentionOf = retentionOf,
       _now = now ?? DateTime.now {
    ready = _load();
  }

  @visibleForTesting
  MessageIndex.forTesting(
    DatabaseApi Function() database, {
    bool Function()? canPersist,
    Duration persistDelay = Duration.zero,
    RetentionPolicy? Function(String roomId)? retentionOf,
    DateTime Function()? now,
  }) : this._(
         database,
         canPersist ?? _defaultCanPersist,
         persistDelay,
         retentionOf: retentionOf,
         now: now,
       );

  static const documentKey = 'com.swovo.odango.search.v1';
  static const maxEntries = 5000;
  static const maxPendingEdits = 200;
  static const maxDocumentBytes = 2 * 1024 * 1024;
  static const defaultPersistDelay = Duration(seconds: 3);
  static const _maxRowsRead = maxEntries * 4;
  static const _documentOverhead = 32;

  static final _indexes = Expando<MessageIndex>('MessageIndex');

  static bool _defaultCanPersist() => !kIsWeb && !isDatabaseUnencrypted;

  static MessageIndex of(Client client) {
    final existing = _indexes[client];
    if (existing != null) return existing;
    final index = MessageIndex._(
      () => client.database,
      _defaultCanPersist,
      defaultPersistDelay,
      retentionOf: (roomId) {
        final room = client.getRoomById(roomId);
        return room == null ? null : RetentionPolicy.forRoom(room);
      },
    );
    // The SDK emptied its event tables: what was searchable is gone with it.
    index._wipeWhenCacheIsCleared(client);
    return _indexes[client] = index;
  }

  static void forget(Client client) {
    _indexes[client]?._stopListening();
    _indexes[client] = null;
  }

  StreamSubscription<bool>? _cacheCleared;

  void _wipeWhenCacheIsCleared(Client client) {
    _cacheCleared = client.onCacheCleared.stream.listen(
      (_) => unawaited(wipe()),
    );
  }

  void _stopListening() {
    unawaited(_cacheCleared?.cancel());
    _cacheCleared = null;
  }

  final DatabaseApi Function() _database;
  final bool Function() _canPersist;
  final Duration _persistDelay;
  final RetentionPolicy? Function(String roomId)? _retentionOf;
  final DateTime Function() _now;
  final _entries = <String, IndexedMessage>{};

  /// When the edit that is in the text of an entry was sent, and edits that
  /// arrived before their message did (history is read newest first). Both
  /// only live in memory.
  final _editedAt = <String, int>{};
  final _pendingEdits = <String, _PendingEdit>{};
  var _epoch = 0;

  /// Changes every time the index is wiped.
  int get epoch => _epoch;
  var _dirty = false;
  var _loadFailed = false;
  Timer? _timer;
  Future<void> _queue = Future.value();

  /// Completes when the stored index is loaded. Never throws.
  late final Future<void> ready;

  int get length => _entries.length;

  /// False where the index only lives in memory.
  bool get persistent => _canPersist();

  List<IndexedMessage> snapshot() => List.unmodifiable(_entries.values);

  Future<void> _load() async {
    if (!_canPersist()) return;
    await _loadDocument();
  }

  Future<void> _loadDocument() async {
    final epoch = _epoch;
    try {
      final cached = await _database().getCustomCacheObject(documentKey);
      if (epoch != _epoch) return;
      _loadFailed = false;
      if (cached == null) return;
      for (final entry in parse(cached.content)) {
        _entries.putIfAbsent(entry.key, () => entry);
      }
      _evictOverCap();
      _dropExpired();
    } catch (_) {
      if (epoch != _epoch) return;
      _loadFailed = true;
      Logs().w('[Search] index storage unavailable');
    }
  }

  /// The valid rows of a stored document, newest [maxEntries] only. Anything
  /// that does not look exactly like a row this class wrote is dropped.
  @visibleForTesting
  static List<IndexedMessage> parse(Object? document) {
    if (document is! Map || document['v'] != 1) return const [];
    final rows = document['e'];
    if (rows is! List) return const [];
    final parsed = <IndexedMessage>[];
    for (final row in rows.take(_maxRowsRead)) {
      final entry = _parseRow(row);
      if (entry != null) parsed.add(entry);
    }
    if (parsed.length <= maxEntries) return parsed;
    parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return parsed.take(maxEntries).toList();
  }

  static IndexedMessage? _parseRow(Object? row) {
    if (row is! List || row.length != 7) return null;
    final [roomId, eventId, senderId, ts, kind, flags, text] = row;
    if (roomId is! String || !isMatrixRoomId(roomId)) return null;
    if (!isMatrixEventId(eventId)) return null;
    if (senderId is! String ||
        !senderId.startsWith('@') ||
        !senderId.isValidMatrixIdStrict()) {
      return null;
    }
    if (ts is! int || ts <= 0) return null;
    if (kind is! int || kind < 0 || kind >= SearchKind.values.length) {
      return null;
    }
    if (flags is! int || flags < 0 || flags > 3) return null;
    if (text is! String || text.isEmpty) return null;
    return IndexedMessage(
      roomId: roomId,
      eventId: eventId as String,
      senderId: senderId,
      timestamp: ts,
      kind: SearchKind.values[kind],
      text: text.characters.take(IndexPolicy.maxTextChars).toString(),
      mentionsMe: flags & 1 != 0,
      hasLink: flags & 2 != 0,
    );
  }

  void add(IndexedMessage message) {
    if (_editedAt.containsKey(message.key) &&
        _entries.containsKey(message.key)) {
      return;
    }
    _entries[message.key] = message;
    final pending = _pendingEdits.remove(message.key);
    if (pending != null) {
      applyEdit(
        roomId: message.roomId,
        targetId: message.eventId,
        editorId: pending.editorId,
        newText: pending.text,
        at: pending.at,
      );
    }
    _evictOverCap();
    _markDirty();
  }

  void _evictOverCap() {
    while (_entries.length > maxEntries) {
      final oldest = _entries.values.reduce(
        (a, b) => a.timestamp <= b.timestamp ? a : b,
      );
      _entries.remove(oldest.key);
    }
  }

  /// Replaces the text of a message, only when [editorId] wrote it and the
  /// edit is newer than the one the text already has. [at] is the time the
  /// edit was sent. An edit of a message that is not known yet is kept
  /// (a few of them) until the message arrives.
  void applyEdit({
    required String roomId,
    required String targetId,
    required String editorId,
    required String newText,
    required int at,
  }) {
    final key = '$roomId\n$targetId';
    final existing = _entries[key];
    if (existing == null) {
      final pending = _pendingEdits[key];
      if (pending != null && pending.at >= at) return;
      _pendingEdits.remove(key);
      _pendingEdits[key] = _PendingEdit(editorId, newText, at);
      while (_pendingEdits.length > maxPendingEdits) {
        _pendingEdits.remove(_pendingEdits.keys.first);
      }
      return;
    }
    if (existing.senderId != editorId || at <= (_editedAt[key] ?? 0)) return;
    _editedAt[key] = at;
    _entries[key] = existing.withText(
      newText,
      hasLink: IndexPolicy.containsLink(newText),
    );
    _markDirty();
  }

  void remove(String roomId, String eventId) {
    final key = '$roomId\n$eventId';
    _editedAt.remove(key);
    _pendingEdits.remove(key);
    if (_entries.remove(key) != null) _markDirty();
  }

  void removeRoom(String roomId) {
    final before = _entries.length;
    final prefix = '$roomId\n';
    _editedAt.removeWhere((key, _) => key.startsWith(prefix));
    _pendingEdits.removeWhere((key, _) => key.startsWith(prefix));
    _entries.removeWhere((_, entry) => entry.roomId == roomId);
    if (_entries.length != before) _markDirty();
  }

  /// Drops what the retention timers of the rooms hide: nothing the user can
  /// no longer see stays searchable. Returns how many entries were dropped.
  int pruneRetention(
    RetentionPolicy? Function(String roomId) policyOf,
    DateTime now,
  ) {
    final before = _entries.length;
    _entries.removeWhere(
      (_, entry) =>
          policyOf(entry.roomId)?.hidesAt(
            DateTime.fromMillisecondsSinceEpoch(entry.timestamp),
            entry.kind.eventType,
            now,
          ) ==
          true,
    );
    final dropped = before - _entries.length;
    if (dropped > 0) _markDirty();
    return dropped;
  }

  /// Expired entries never stay in the stored document: this runs on load and
  /// before every write, not only when the search page is open.
  void _dropExpired() {
    final policyOf = _retentionOf;
    if (policyOf != null) pruneRetention(policyOf, _now());
  }

  /// Forgets everything, in memory and in the database. Never throws.
  Future<void> wipe() {
    _epoch++;
    _entries.clear();
    _editedAt.clear();
    _pendingEdits.clear();
    _dirty = false;
    _loadFailed = false;
    _timer?.cancel();
    _timer = null;
    return _queue = _queue.then((_) => _writeTombstone());
  }

  Future<void> _writeTombstone() async {
    try {
      await _database().cacheCustomObject(documentKey, {
        'v': 1,
        'e': <Object?>[],
      });
    } catch (_) {
      Logs().w('[Search] index storage unavailable');
    }
  }

  void _markDirty() {
    if (!_canPersist()) return;
    _dirty = true;
    _timer ??= Timer(_persistDelay, () {
      _timer = null;
      unawaited(_enqueuePersist());
    });
  }

  /// Writes what is pending now instead of after the delay.
  @visibleForTesting
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_dirty) unawaited(_enqueuePersist());
    return _queue;
  }

  Future<void> _enqueuePersist() => _queue = _queue.then((_) => _persist());

  /// A document that could not be read is never overwritten: the index reads
  /// it again first and writes nothing while it stays unreadable.
  Future<void> _persist() async {
    if (!_dirty || !_canPersist()) return;
    if (_loadFailed) {
      await _loadDocument();
      if (_loadFailed) return;
    }
    try {
      _dropExpired();
      final document = _document();
      _dirty = false;
      await _database().cacheCustomObject(documentKey, document);
    } catch (_) {
      _dirty = true;
      Logs().w('[Search] index storage unavailable');
    }
  }

  /// The newest entries that fit [maxDocumentBytes]; the rest is forgotten.
  Map<String, Object?> _document() {
    final sorted = _entries.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final rows = <List<Object?>>[];
    var bytes = _documentOverhead;
    for (final entry in sorted) {
      final row = [
        entry.roomId,
        entry.eventId,
        entry.senderId,
        entry.timestamp,
        entry.kind.index,
        (entry.mentionsMe ? 1 : 0) | (entry.hasLink ? 2 : 0),
        entry.text,
      ];
      bytes += utf8.encode(jsonEncode(row)).length + 1;
      if (bytes > maxDocumentBytes) break;
      rows.add(row);
    }
    if (rows.length < _entries.length) {
      final kept = {for (final row in rows) '${row.first}\n${row[1]}'};
      _entries.removeWhere((key, _) => !kept.contains(key));
    }
    return {'v': 1, 'e': rows};
  }
}

class _PendingEdit {
  const _PendingEdit(this.editorId, this.text, this.at);

  final String editorId;
  final String text;
  final int at;
}
