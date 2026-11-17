// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/format_state.dart';
import 'package:fluffychat/utils/rich_text/html_serializer.dart';
import 'package:fluffychat/utils/rich_text/outgoing_message.dart';
import 'package:fluffychat/utils/rich_text/send_rich_message.dart';
import 'package:fluffychat/utils/scheduling/scheduled_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

RichOutgoing rich(String text, List<FormatRange> ranges) =>
    planOutgoing(text, FormatState(ranges: ranges)) as RichOutgoing;

void main() {
  late Room room;

  setUp(() async {
    final client = await prepareTestClient();
    room = Room(id: '!localpart:server.abc', client: client);
  });

  Event event(String id, {String sender = '@bob:server.abc'}) => Event(
    eventId: id,
    type: EventTypes.Message,
    content: {'msgtype': 'm.text', 'body': 'hi'},
    senderId: sender,
    originServerTs: DateTime(2025),
    room: room,
  );

  group('build', () {
    test('rich text is the exact map of the W05 send path', () {
      final message = rich('the SECRET <b>&', [
        const FormatRange(4, 10, RangeKind.spoiler),
        const FormatRange(11, 15, RangeKind.bold),
      ]);
      expect(
        ScheduledContent.build(room, message),
        richMessageContent(room, message),
      );
    });

    test('plain text is a body with no markup', () {
      expect(ScheduledContent.build(room, const PlainOutgoing('hello')), {
        'msgtype': 'm.text',
        'body': 'hello',
      });
    });

    test('plain text carries the mentions of the text', () {
      final content = ScheduledContent.build(
        room,
        const PlainOutgoing('hey @alice:example.org and @room'),
      );
      expect(content['m.mentions'], {
        'room': true,
        'user_ids': ['@alice:example.org'],
      });
    });

    test('the silent flag is set only on request', () {
      expect(
        ScheduledContent.build(room, const PlainOutgoing('a')),
        isNot(contains(ScheduledContent.silentKey)),
      );
      expect(
        ScheduledContent.build(
          room,
          const PlainOutgoing('a'),
          silent: true,
        )[ScheduledContent.silentKey],
        true,
      );
    });

    test('a reply points at the event and mentions its sender', () {
      final content = ScheduledContent.build(
        room,
        const PlainOutgoing('yes'),
        inReplyTo: event(r'$reply'),
      );
      expect(content['m.relates_to'], {
        'm.in_reply_to': {'event_id': r'$reply'},
      });
      expect(content['m.mentions'], {
        'user_ids': ['@bob:server.abc'],
      });
    });

    test('a thread message falls back to the root', () {
      final content = ScheduledContent.build(
        room,
        const PlainOutgoing('in thread'),
        threadRootEventId: r'$root',
      );
      expect(content['m.relates_to'], {
        'rel_type': 'm.thread',
        'event_id': r'$root',
        'is_falling_back': true,
        'm.in_reply_to': {'event_id': r'$root'},
      });
    });

    test('a reply inside a thread is not a fallback', () {
      final content = ScheduledContent.build(
        room,
        const PlainOutgoing('in thread'),
        inReplyTo: event(r'$reply'),
        threadRootEventId: r'$root',
      );
      expect(content['m.relates_to'], {
        'rel_type': 'm.thread',
        'event_id': r'$root',
        'is_falling_back': false,
        'm.in_reply_to': {'event_id': r'$reply'},
      });
    });

    test('text over the byte cap is refused', () {
      expect(
        () => ScheduledContent.build(
          room,
          PlainOutgoing('a' * (RichLimits.maxBodyBytes + 1)),
        ),
        throwsA(isA<RichTextTooLong>()),
      );
    });

    test('everything build makes passes validate unchanged', () {
      final content = ScheduledContent.build(
        room,
        const PlainOutgoing('hey @alice:example.org'),
        inReplyTo: event(r'$reply'),
        threadRootEventId: r'$root',
        silent: true,
      );
      expect(ScheduledContent.validate(content), content);
    });
  });

  group('validate', () {
    Map<String, Object?> base() => {'msgtype': 'm.text', 'body': 'hello'};

    test('accepts the minimal map', () {
      expect(ScheduledContent.validate(base()), base());
    });

    test('rejects anything but a string keyed map', () {
      expect(ScheduledContent.validate(null), isNull);
      expect(ScheduledContent.validate('text'), isNull);
      expect(ScheduledContent.validate({1: 'a'}), isNull);
    });

    test('drops unknown keys', () {
      final cleaned = ScheduledContent.validate({
        ...base(),
        'url': 'mxc://evil/x',
        'info': {'a': 1},
      });
      expect(cleaned, base());
    });

    test('rejects other message types and a missing or empty body', () {
      expect(
        ScheduledContent.validate({...base(), 'msgtype': 'm.image'}),
        isNull,
      );
      expect(ScheduledContent.validate({'msgtype': 'm.text'}), isNull);
      expect(ScheduledContent.validate({...base(), 'body': ''}), isNull);
      expect(ScheduledContent.validate({...base(), 'body': 5}), isNull);
    });

    test('rejects a body over the byte cap', () {
      expect(
        ScheduledContent.validate({
          ...base(),
          'body': 'ä' * RichLimits.maxBodyBytes,
        }),
        isNull,
      );
    });

    test('html needs the format and stays within its cap', () {
      final html = {
        ...base(),
        'format': 'org.matrix.custom.html',
        'formatted_body': '<b>hello</b>',
      };
      expect(ScheduledContent.validate(html), html);
      expect(
        ScheduledContent.validate({...base(), 'formatted_body': '<b>x</b>'}),
        isNull,
      );
      expect(
        ScheduledContent.validate({
          ...base(),
          'format': 'other',
          'formatted_body': 'x',
        }),
        isNull,
      );
      expect(
        ScheduledContent.validate({
          ...html,
          'formatted_body': 'a' * (RichLimits.maxHtmlBytes + 1),
        }),
        isNull,
      );
    });

    test('mentions: valid ids pass, junk is rejected', () {
      final ok = {
        ...base(),
        'm.mentions': {
          'room': true,
          'user_ids': ['@alice:example.org'],
        },
      };
      expect(ScheduledContent.validate(ok), ok);
      expect(
        ScheduledContent.validate({
          ...base(),
          'm.mentions': {
            'user_ids': ['not an id'],
          },
        }),
        isNull,
      );
      expect(
        ScheduledContent.validate({
          ...base(),
          'm.mentions': {
            'user_ids': [for (var i = 0; i < 101; i++) '@u$i:example.org'],
          },
        }),
        isNull,
      );
    });

    test('relations: only the known shapes with event ids', () {
      final reply = {
        ...base(),
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$a'},
        },
      };
      expect(ScheduledContent.validate(reply), reply);
      expect(
        ScheduledContent.validate({
          ...base(),
          'm.relates_to': {
            'm.in_reply_to': {'event_id': 'not-an-event-id'},
          },
        }),
        isNull,
      );
      expect(
        ScheduledContent.validate({
          ...base(),
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$a'},
        }),
        isNull,
      );
      expect(
        ScheduledContent.validate({
          ...base(),
          'm.relates_to': {
            'rel_type': 'm.thread',
            'event_id': '\$${'a' * 300}',
            'is_falling_back': true,
            'm.in_reply_to': {'event_id': r'$a'},
          },
        }),
        isNull,
      );
    });

    test('the silent flag is kept only as true', () {
      expect(
        ScheduledContent.validate({
          ...base(),
          ScheduledContent.silentKey: true,
        }),
        {...base(), ScheduledContent.silentKey: true},
      );
      expect(
        ScheduledContent.validate({
          ...base(),
          ScheduledContent.silentKey: 'yes',
        }),
        isNull,
      );
    });

    test('the whole event stays within the event cap', () {
      final big = {
        ...base(),
        'format': 'org.matrix.custom.html',
        'formatted_body': 'a' * RichLimits.maxHtmlBytes,
        'body': 'a' * RichLimits.maxBodyBytes,
        'm.mentions': {
          'user_ids': [
            for (var i = 0; i < 100; i++) '@user$i:${'x' * 200}.org',
          ],
        },
      };
      final mentionsOnly = {
        'msgtype': 'm.text',
        'body': 'a',
        'm.mentions': big['m.mentions'],
      };
      expect(ScheduledContent.validate(mentionsOnly), isNotNull);
      expect(
        utf8.encode(jsonEncode(big)).length,
        greaterThan(RichLimits.maxEventBytes),
      );
      expect(ScheduledContent.validate(big), isNull);
    });
  });

  group('previewOf', () {
    test('collapses whitespace and cuts at 500 characters', () {
      expect(ScheduledContent.previewOf({'body': ' a \n\n b '}), 'a b');
      expect(
        ScheduledContent.previewOf({'body': 'ä' * 600}).characters.length,
        500,
      );
    });
  });
}
