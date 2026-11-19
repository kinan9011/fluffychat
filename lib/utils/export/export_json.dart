// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:odango/utils/export/export_model.dart';

const _secretKeys = {'key', 'iv', 'hashes'};
const _encryptedFileKeys = {'file', 'thumbnail_file'};

/// A copy of an event's content that is safe to write to a file: bounded in
/// depth, node count and string length, only String keys, and without the
/// decryption secrets (`key`, `iv`, `hashes`) of an encrypted attachment: with
/// them anyone who can download the media from the server could read it.
Map<String, Object?> scrubContent(Map<String, Object?> content) {
  var nodes = 0;
  Object? walk(Object? value, int depth, bool insideFile) {
    if (++nodes > ExportLimits.maxJsonNodes) return null;
    if (depth > ExportLimits.maxJsonDepth) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      return value.length > ExportLimits.maxTextPerMessage
          ? '${value.substring(0, ExportLimits.maxTextPerMessage)}…'
          : value;
    }
    if (value is List) {
      return [for (final item in value) walk(item, depth + 1, insideFile)];
    }
    if (value is Map) {
      final out = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) continue;
        if (insideFile && _secretKeys.contains(key)) continue;
        out[key] = walk(
          entry.value,
          depth + 1,
          _encryptedFileKeys.contains(key),
        );
      }
      return out;
    }
    return null;
  }

  return walk(content, 0, false)! as Map<String, Object?>;
}

/// The same text as one pretty printed document, written event by event so
/// that a chat over [maxLength] stops with [ExportTooLarge] while it is built
/// instead of after it exists in memory.
String buildJson(
  ExportMeta meta,
  List<ExportEvent> events, {
  int maxLength = ExportLimits.maxTextOutputBytes,
}) {
  const encoder = JsonEncoder.withIndent('  ');
  final head = encoder.convert({
    'format': 'com.swovo.odango.export',
    'version': 1,
    'exported_at': meta.exportedAt.toUtc().toIso8601String(),
    'truncated': meta.truncated,
    'room': {
      'id': meta.roomId,
      'name': meta.roomName,
      'encrypted': meta.encrypted,
    },
  });
  final out = StringBuffer(head.substring(0, head.length - 2));
  if (events.isEmpty) return (out..write(',\n  "events": []\n}')).toString();
  out.write(',\n  "events": [');
  var first = true;
  for (final event in events) {
    final item = encoder.convert({
      'event_id': event.eventId,
      'sender': event.senderId,
      'origin_server_ts': event.time.toUtc().millisecondsSinceEpoch,
      'type': event.type,
      'content': scrubContent(event.content),
    });
    out
      ..write(first ? '\n    ' : ',\n    ')
      ..write(item.replaceAll('\n', '\n    '));
    first = false;
    if (out.length > maxLength) throw const ExportTooLarge();
  }
  out.write('\n  ]\n}');
  return out.toString();
}
