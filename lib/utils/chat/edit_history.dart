// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

class EditVersion {
  const EditVersion({
    required this.eventId,
    required this.time,
    required this.text,
  });

  final String eventId;
  final DateTime time;
  final String text;
}

class EditHistory {
  const EditHistory({required this.original, required this.edits});

  final EditVersion original;

  /// Oldest first; the last one is the current text.
  final List<EditVersion> edits;
}

String _cut(String text) =>
    text.characters.take(RichLimits.maxEditUnits).toString();

/// The versions of [original] from the events that claim to edit it. Edits
/// come from the homeserver and from other users: only the author's own
/// `m.replace` events of this event with a text body count.
EditHistory? buildEditHistory({
  required Event original,
  required String originalText,
  required Iterable<Event> candidates,
}) {
  final byId = <String, EditVersion>{};
  for (final event in candidates) {
    if (event.senderId != original.senderId ||
        event.type != EventTypes.Message ||
        event.redacted) {
      continue;
    }
    final relation = event.content['m.relates_to'];
    final content = event.content['m.new_content'];
    if (relation is! Map ||
        relation['rel_type'] != RelationshipTypes.edit ||
        relation['event_id'] != original.eventId ||
        content is! Map) {
      continue;
    }
    final body = content['body'];
    if (body is! String || body.trim().isEmpty) continue;
    byId[event.eventId] = EditVersion(
      eventId: event.eventId,
      time: event.originServerTs,
      text: _cut(body),
    );
  }
  if (byId.isEmpty) return null;
  final sorted = byId.values.toList()
    ..sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.eventId.compareTo(b.eventId);
    });
  return EditHistory(
    original: EditVersion(
      eventId: original.eventId,
      time: original.originServerTs,
      text: _cut(originalText),
    ),
    edits: sorted.length > RichLimits.maxEdits
        ? sorted.sublist(sorted.length - RichLimits.maxEdits)
        : sorted,
  );
}

/// The newest page of the relations of [original] from the user's own homeserver,
/// decrypted where needed. Every failure gives an empty list; the response is
/// untrusted and validated by [buildEditHistory].
Future<List<Event>> fetchEditEvents(Room room, Event original) async {
  try {
    final response = await room.client.getRelatingEventsWithRelType(
      room.id,
      original.eventId,
      RelationshipTypes.edit,
      limit: RichLimits.maxEdits,
      dir: Direction.b,
    );
    final events = <Event>[];
    for (final raw in response.chunk.take(RichLimits.maxEdits)) {
      var event = Event.fromMatrixEvent(raw, room);
      if (event.type == EventTypes.Encrypted) {
        event = await room.client.encryption?.decryptRoomEvent(event) ?? event;
      }
      events.add(event);
    }
    return events;
  } catch (_) {
    return const [];
  }
}
