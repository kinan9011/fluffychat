// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';
import 'package:odango/utils/logged_in_database.dart';
import 'package:odango/utils/matrix_room_id.dart';

class DraftEntry {
  const DraftEntry(this.text, {this.format});

  final String text;
  final Map<String, Object?>? format;
}

class _Draft {
  _Draft(this.text, this.format, this.timestamp);

  final String text;
  final Map<String, Object?>? format;
  final int timestamp;
}

/// Unsent composer text, one document per account inside that account's
/// database (encrypted on native platforms; on the web and on a fallback
/// without a keyring it is not, and the app says so). Nothing is written to
/// the shared preferences and
/// nothing is logged except constant strings.
class DraftStore {
  DraftStore._(this._database, this._now) {
    ready = _load();
  }

  @visibleForTesting
  DraftStore.forTesting(DatabaseApi Function() database, {int Function()? now})
    : this._(database, now ?? _wallClock);

  static const documentKey = 'com.swovo.odango.drafts.v1';
  static const maxDrafts = 50;
  static const maxDraftChars = 8000;
  static const maxFormatJsonUnits = 16384;
  static const maxDocumentBytes = 1048576;

  static final _stores = Expando<DraftStore>('DraftStore');
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  static DraftStore of(Client client) {
    final existing = _stores[client];
    if (existing != null) return existing;
    final store = DraftStore._(() => loggedInDatabase(client), _wallClock);
    // The SDK wipes its custom cache objects with `clearCache()`: write the
    // drafts again so a cleared cache does not silently drop them.
    client.onCacheCleared.stream.listen(
      (_) => unawaited(store.ready.then((_) => store._enqueuePersist())),
    );
    return _stores[client] = store;
  }

  static void forget(Client client) => _stores[client] = null;

  static bool isRoomId(String id) => isMatrixRoomId(id);

  final DatabaseApi Function() _database;
  final int Function() _now;
  final _drafts = <String, _Draft>{};
  final _touched = <String>{};
  var _loaded = false;
  var _loadFailed = false;
  Future<void> _queue = Future.value();

  /// Completes when the stored drafts are loaded. Never throws.
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      await _loadDocument();
    } finally {
      _loaded = true;
    }
  }

  Future<void> _loadDocument() async {
    try {
      final cached = await _database().getCustomCacheObject(documentKey);
      _loadFailed = false;
      if (cached == null) return;
      for (final entry in _parse(cached.content).entries) {
        if (!_touched.contains(entry.key)) _drafts[entry.key] = entry.value;
      }
      if (_drafts.isNotEmpty) revision.value++;
    } catch (_) {
      _loadFailed = true;
      Logs().w('[Drafts] storage unavailable');
    }
  }

  static Map<String, _Draft> _parse(Object? document) {
    if (document is! Map || document['v'] != 1) return {};
    final drafts = document['drafts'];
    if (drafts is! Map) return {};
    final parsed = <String, _Draft>{};
    for (final entry in drafts.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !isRoomId(key) || value is! Map) continue;
      final text = value['t'];
      if (text is! String || text.trim().isEmpty) continue;
      final format = value['f'];
      final ts = value['ts'];
      parsed[key] = _Draft(
        _cut(text),
        format is Map && jsonEncode(format).length <= maxFormatJsonUnits
            ? Map<String, Object?>.from(format)
            : null,
        ts is int ? ts : 0,
      );
    }
    if (parsed.length <= maxDrafts) return parsed;
    final newest = parsed.entries.toList()
      ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
    return Map.fromEntries(newest.take(maxDrafts));
  }

  static String _cut(String text) =>
      text.characters.take(maxDraftChars).toString();

  DraftEntry? read(String roomId) {
    final draft = _drafts[roomId];
    return draft == null ? null : DraftEntry(draft.text, format: draft.format);
  }

  /// The draft as the chat list shows it: nothing for a blank draft.
  String? readForDisplay(String roomId) {
    final text = read(roomId)?.text;
    return text == null || text.trim().isEmpty ? null : text;
  }

  Future<void> write(
    String roomId,
    String text, {
    Map<String, Object?>? format,
  }) async {
    if (text.trim().isEmpty) return remove(roomId);
    if (!isRoomId(roomId)) return;
    _store(roomId, text, format);
    revision.value++;
    await ready;
    await _enqueuePersist();
  }

  void _store(String roomId, String text, Map<String, Object?>? format) {
    _touched.add(roomId);
    _drafts[roomId] = _Draft(
      _cut(text),
      format != null && jsonEncode(format).length <= maxFormatJsonUnits
          ? format
          : null,
      _now(),
    );
    _evictOldest(() => _drafts.length > maxDrafts);
  }

  void _evictOldest(bool Function() tooMany) {
    while (tooMany() && _drafts.isNotEmpty) {
      final oldest = _drafts.entries.reduce(
        (a, b) => a.value.timestamp <= b.value.timestamp ? a : b,
      );
      _drafts.remove(oldest.key);
    }
  }

  Future<void> remove(String roomId) async {
    final existed = _drafts.remove(roomId) != null;
    if (!existed && _loaded && !_loadFailed) return;
    _touched.add(roomId);
    revision.value++;
    await ready;
    await _enqueuePersist();
  }

  /// Takes over a draft from the old plaintext storage. True only when the
  /// stored document reads back with that room's draft; an existing draft is
  /// never overwritten.
  Future<bool> importLegacy(String roomId, String text) async {
    await ready;
    if (!isRoomId(roomId) || text.trim().isEmpty) return false;
    if (!_drafts.containsKey(roomId)) {
      _store(roomId, text, null);
      revision.value++;
    }
    await _enqueuePersist();
    try {
      final cached = await _database().getCustomCacheObject(documentKey);
      final stored = _parse(cached?.content)[roomId];
      return stored != null && stored.text == _drafts[roomId]?.text;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  Future<void> flush() => _queue;

  Future<void> _enqueuePersist() => _queue = _queue.then((_) => _persist());

  Map<String, Object?> _document() => {
    'v': 1,
    'drafts': {
      for (final entry in _drafts.entries)
        entry.key: {
          't': entry.value.text,
          'f': ?entry.value.format,
          'ts': entry.value.timestamp,
        },
    },
  };

  /// A document that could not be read is never overwritten: the store reads
  /// it again first and writes nothing while it stays unreadable.
  Future<void> _persist() async {
    if (_loadFailed) {
      await _loadDocument();
      if (_loadFailed) return;
    }
    try {
      _evictOldest(
        () => utf8.encode(jsonEncode(_document())).length > maxDocumentBytes,
      );
      await _database().cacheCustomObject(documentKey, _document());
    } catch (_) {
      Logs().w('[Drafts] storage unavailable');
    }
  }

  static String preview(String draft) => draft
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .characters
      .take(120)
      .toString();
}
