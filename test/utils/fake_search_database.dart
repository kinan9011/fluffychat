// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:matrix/matrix.dart';

/// A database with only the calls the search code makes. Counts them, can
/// hold a write back, fail, or serve a room's stored events.
class FakeSearchDatabase implements DatabaseApi {
  final stored = <String, Map<String, Object?>>{};
  final events = <String, List<Event>>{};
  var reads = 0;
  var writes = 0;
  var eventReads = 0;
  var failReads = false;
  var failWrites = false;

  /// The next write waits for it before it takes effect.
  Completer<void>? writeGate;

  /// While set, every read waits for it before it answers.
  Completer<void>? readGate;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {
    writes++;
    if (failWrites) throw StateError('SENTINEL-DB-FAILURE');
    final gate = writeGate;
    writeGate = null;
    await gate?.future;
    stored[cacheKey] = object;
  }

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async {
    reads++;
    if (failReads) throw StateError('SENTINEL-DB-FAILURE');
    await readGate?.future;
    final content = stored[cacheKey];
    return content == null ? null : (content: content, savedAt: DateTime.now());
  }

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    eventReads++;
    final all = events[room.id] ?? const <Event>[];
    return all.skip(start).take(limit ?? all.length).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
