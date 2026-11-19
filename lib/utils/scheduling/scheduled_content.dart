// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/rich_text/outgoing_message.dart';
import 'package:odango/utils/rich_text/rich_mentions.dart';
import 'package:odango/utils/rich_text/send_rich_message.dart';

/// The event content of a message sent through the send options (silent,
/// scheduled, when online). Built once, validated again whenever it comes
/// back from storage.
abstract class ScheduledContent {
  static const silentKey = 'com.swovo.odango.silent';
  static const maxMentions = 100;
  static const maxEventIdLength = 255;
  static const maxPreviewChars = 500;

  static Map<String, Object?> build(
    Room room,
    OutgoingText outgoing, {
    Event? inReplyTo,
    String? threadRootEventId,
    bool silent = false,
  }) {
    final content = switch (outgoing) {
      RichOutgoing() => richMessageContent(
        room,
        outgoing,
        repliedToSender: inReplyTo?.senderId,
      ),
      PlainOutgoing(:final text) => {
        'msgtype': MessageTypes.Text,
        'body': text,
        'm.mentions': ?richMentions(
          plainText: text,
          resolve: room.getMention,
          ownUserId: room.client.userID,
          repliedToSender: inReplyTo?.senderId,
        ),
      },
    };
    final replyId = inReplyTo?.eventId;
    if (threadRootEventId != null) {
      content['m.relates_to'] = {
        'rel_type': 'm.thread',
        'event_id': threadRootEventId,
        'is_falling_back': replyId == null,
        'm.in_reply_to': {'event_id': replyId ?? threadRootEventId},
      };
    } else if (replyId != null) {
      content['m.relates_to'] = {
        'm.in_reply_to': {'event_id': replyId},
      };
    }
    if (silent) content[silentKey] = true;
    final checked = validate(content);
    if (checked == null) throw const RichTextTooLong('event');
    return checked;
  }

  static bool isSilent(Map<String, Object?> content) =>
      content[silentKey] == true;

  static String previewOf(Map<String, Object?> content) {
    final body = content['body'];
    if (body is! String) return '';
    return body
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .characters
        .take(maxPreviewChars)
        .toString();
  }

  /// A cleaned copy of [content], or null when it is not a message this app
  /// could have scheduled. Unknown keys are dropped.
  static Map<String, Object?>? validate(Object? content) {
    if (content is! Map || content.keys.any((k) => k is! String)) return null;
    if (content['msgtype'] != MessageTypes.Text) return null;
    final body = content['body'];
    if (body is! String ||
        body.isEmpty ||
        _bytes(body) > RichLimits.maxBodyBytes) {
      return null;
    }
    final cleaned = <String, Object?>{
      'msgtype': MessageTypes.Text,
      'body': body,
    };

    final format = content['format'];
    final html = content['formatted_body'];
    if ((format == null) != (html == null)) return null;
    if (format != null) {
      if (format != 'org.matrix.custom.html' ||
          html is! String ||
          _bytes(html) > RichLimits.maxHtmlBytes) {
        return null;
      }
      cleaned['format'] = format;
      cleaned['formatted_body'] = html;
    }

    if (content.containsKey('m.mentions')) {
      final mentions = _mentions(content['m.mentions']);
      if (mentions == null) return null;
      cleaned['m.mentions'] = mentions;
    }
    if (content.containsKey('m.relates_to')) {
      final relation = _relation(content['m.relates_to']);
      if (relation == null) return null;
      cleaned['m.relates_to'] = relation;
    }
    if (content.containsKey(silentKey)) {
      if (content[silentKey] != true) return null;
      cleaned[silentKey] = true;
    }
    if (_bytes(jsonEncode(cleaned)) > RichLimits.maxEventBytes) return null;
    return cleaned;
  }

  static int _bytes(String value) => utf8.encode(value).length;

  static Map<String, Object?>? _mentions(Object? value) {
    if (value is! Map) return null;
    final room = value['room'];
    final ids = value['user_ids'];
    if (room != null && room is! bool) return null;
    if (ids != null) {
      if (ids is! List ||
          ids.length > maxMentions ||
          ids.any(
            (id) =>
                id is! String ||
                !id.startsWith('@') ||
                !id.isValidMatrixIdStrict(),
          )) {
        return null;
      }
    }
    return {
      'room': ?room,
      'user_ids': ?ids == null ? null : List<String>.from(ids),
    };
  }

  static bool _eventId(Object? id) =>
      id is String &&
      id.startsWith(r'$') &&
      id.length > 1 &&
      id.length <= maxEventIdLength;

  static Map<String, Object?>? _reply(Object? value) {
    if (value is! Map || !_eventId(value['event_id'])) return null;
    return {'event_id': value['event_id']};
  }

  static Map<String, Object?>? _relation(Object? value) {
    if (value is! Map) return null;
    final reply = value.containsKey('m.in_reply_to')
        ? _reply(value['m.in_reply_to'])
        : null;
    if (value['rel_type'] == null) {
      if (reply == null) return null;
      return {'m.in_reply_to': reply};
    }
    if (value['rel_type'] != 'm.thread' ||
        !_eventId(value['event_id']) ||
        value['is_falling_back'] is! bool ||
        reply == null) {
      return null;
    }
    return {
      'rel_type': 'm.thread',
      'event_id': value['event_id'],
      'is_falling_back': value['is_falling_back'],
      'm.in_reply_to': reply,
    };
  }
}
