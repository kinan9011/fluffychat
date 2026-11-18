// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:fluffychat/utils/polls/poll_content.dart';
import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

/// Which events become searchable entries. Matrix content is untrusted: every
/// field is type-checked, nothing is cast.
abstract final class IndexPolicy {
  static const maxTextChars = 500;
  static const _scanChars = maxTextChars * 4;

  static final _link = RegExp('https?://', caseSensitive: false);

  static String cleanText(String raw) => safeDisplayText(
    raw.characters.take(_scanChars).toString(),
    maxGraphemes: _scanChars,
  ).characters.take(maxTextChars).toString();

  static bool containsLink(String text) => _link.hasMatch(text);

  static bool _isUserId(String id) =>
      id.isValidMatrixIdStrict() && id.startsWith('@');

  static bool _isEdit(Event event) {
    final relation = event.content['m.relates_to'];
    return relation is Map && relation['rel_type'] == RelationshipTypes.edit;
  }

  /// The entry for [event], or null when it must not be indexed: not an
  /// encrypted room, redacted, not delivered yet, an edit, not a searchable
  /// kind, malformed ids or time stamp, no text.
  static IndexedMessage? fromEvent(
    Event event, {
    required String ownUserId,
    DateTime? now,
  }) => event.room.encrypted
      ? describe(event, ownUserId: ownUserId, now: now)
      : null;

  /// The same checks without looking at the encryption of the room: used for
  /// results of unencrypted rooms, which are shown but never stored.
  static IndexedMessage? describe(
    Event event, {
    required String ownUserId,
    DateTime? now,
  }) {
    if (event.redacted || !event.status.isSynced) return null;
    if (_isEdit(event)) return null;
    final kind = searchKindOf(event);
    if (kind == null) return null;
    final roomId = event.room.id;
    final eventId = event.eventId;
    final senderId = event.senderId;
    if (!isMatrixRoomId(roomId) ||
        !isMatrixEventId(eventId) ||
        !_isUserId(senderId)) {
      return null;
    }
    final timestamp = event.originServerTs.millisecondsSinceEpoch;
    final limit = (now ?? DateTime.now()).add(const Duration(days: 1));
    if (timestamp <= 0 || event.originServerTs.isAfter(limit)) return null;
    final raw = kind == SearchKind.poll
        ? PollContent.parse(event.content)?.question
        : _string(event.content['body']);
    if (raw == null) return null;
    final text = cleanText(raw);
    if (text.isEmpty) return null;
    final scanned = raw.characters.take(_scanChars).toString();
    return IndexedMessage(
      roomId: roomId,
      eventId: eventId,
      senderId: senderId,
      timestamp: timestamp,
      kind: kind,
      text: text,
      mentionsMe: _mentionsMe(event.content, scanned, ownUserId),
      hasLink: containsLink(scanned),
    );
  }

  static String? _string(Object? value) => value is String ? value : null;

  static bool _mentionsMe(
    Map<String, Object?> content,
    String body,
    String ownUserId,
  ) {
    final mentions = content['m.mentions'];
    if (mentions is Map) {
      if (mentions['room'] == true) return true;
      final ids = mentions['user_ids'];
      if (ids is List && ids.contains(ownUserId)) return true;
    }
    return ownUserId.isNotEmpty &&
        body.toLowerCase().contains(ownUserId.toLowerCase());
  }

  /// The id of the message that [event] edits and its new text, for an
  /// `m.replace` event with a usable `m.new_content`.
  static ({String targetId, String text})? editOf(Event event) {
    if (!event.room.encrypted ||
        event.redacted ||
        !event.status.isSynced ||
        event.type != EventTypes.Message) {
      return null;
    }
    final relation = event.content['m.relates_to'];
    if (relation is! Map || relation['rel_type'] != RelationshipTypes.edit) {
      return null;
    }
    final target = relation['event_id'];
    final replacement = event.content['m.new_content'];
    if (!isMatrixEventId(target) || replacement is! Map) return null;
    final body = replacement['body'];
    if (body is! String) return null;
    final text = cleanText(body);
    if (text.isEmpty) return null;
    return (targetId: target as String, text: text);
  }

  /// The id of the message that [event] redacts, when it is a usable
  /// redaction.
  static String? redactionTarget(Event event) {
    if (event.type != EventTypes.Redaction) return null;
    final target = event.redacts;
    return isMatrixEventId(target) ? target : null;
  }
}
