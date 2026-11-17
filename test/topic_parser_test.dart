// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/utils/topics/topic.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bidi = String.fromCharCode(0x202e);

  group('isEventId', () {
    test('accepts the ids a server makes', () {
      for (final id in [
        r'$a:example.org',
        r'$Nw0yK_3-PqHcM1aRtYs8FvXz2Lg7bUo9iDkEeJh4WnA',
        r'$abc+def/ghi=:example.org:8448',
      ]) {
        expect(TopicParser.isEventId(id), isTrue, reason: id);
      }
    });

    test('rejects everything else', () {
      for (final id in [
        null,
        5,
        '',
        r'$',
        'abc',
        r'!room:example.org',
        r'$a b',
        '\$a\nb',
        r'$<script>:example.org',
        r'$a:',
        r'$a:exa mple.org',
        '\$${'a' * 300}',
      ]) {
        expect(TopicParser.isEventId(id), isFalse, reason: '$id');
      }
    });
  });

  group('titleFrom', () {
    test('the custom title wins over the body', () {
      expect(
        TopicParser.titleFrom({
          'body': 'body line',
          topicContentKey: {'title': 'Releases', 'icon': 'rocket_launch'},
        }),
        'Releases',
      );
    });

    test('without the key the first line of the body is used', () {
      expect(
        TopicParser.titleFrom({'body': '\n  \nHello topic\nsecond line'}),
        'Hello topic',
      );
    });

    test('a blank or wrong custom title falls back to the body', () {
      expect(
        TopicParser.titleFrom({
          'body': 'fallback',
          topicContentKey: {'title': '   '},
        }),
        'fallback',
      );
      expect(
        TopicParser.titleFrom({
          'body': 'fallback',
          topicContentKey: {'title': 5},
        }),
        'fallback',
      );
      expect(
        TopicParser.titleFrom({'body': 'fallback', topicContentKey: 'x'}),
        'fallback',
      );
    });

    test('no usable text is an empty title', () {
      expect(TopicParser.titleFrom({}), '');
      expect(TopicParser.titleFrom({'body': 5}), '');
      expect(TopicParser.titleFrom({'body': '  \n  '}), '');
    });

    test('control and bidi characters are removed', () {
      expect(TopicParser.titleFrom({'body': 'a${bidi}b\u0000c'}), 'a b c');
    });

    test('a long title is cut to 60 graphemes', () {
      final title = TopicParser.titleFrom({'body': 'x' * 500});
      expect(title.characters.length, TopicParser.titleMax);
    });

    test('markup stays plain text', () {
      expect(
        TopicParser.titleFrom({'body': '<b>bold</b> <img src=x>'}),
        '<b>bold</b> <img src=x>',
      );
    });
  });

  group('iconFrom', () {
    test('only icons of the allowlist', () {
      for (final key in TopicIcons.allowed.keys) {
        expect(
          TopicParser.iconFrom({
            topicContentKey: {'icon': key},
          }),
          key,
        );
      }
    });

    test('anything else falls back to tag', () {
      for (final icon in <Object?>[
        'unknown',
        5,
        null,
        '../../x',
        'a' * 200,
        '',
        'TAG',
      ]) {
        expect(
          TopicParser.iconFrom({
            topicContentKey: {'icon': icon},
          }),
          'tag',
          reason: '$icon',
        );
      }
      expect(TopicParser.iconFrom({}), 'tag');
      expect(TopicParser.iconFrom({topicContentKey: 'x'}), 'tag');
    });
  });

  test('sanitizeTitle is what is sent', () {
    expect(TopicParser.sanitizeTitle('  a\n b${bidi}c  '), 'a b c');
    expect(TopicParser.sanitizeTitle('y' * 100).characters.length, 60);
    expect(TopicParser.sanitizeTitle('   '), '');
  });

  test('hueFor is stable and within 0..359', () {
    final random = Random(3);
    for (var i = 0; i < 1000; i++) {
      final id = '\$${random.nextInt(1 << 30)}:example.org';
      final hue = TopicParser.hueFor(id);
      expect(hue, inInclusiveRange(0, 359));
      expect(TopicParser.hueFor(id), hue);
    }
    expect(TopicParser.hueFor(r'$a:x'), isNot(TopicParser.hueFor(r'$b:x')));
  });

  group('fromRoot', () {
    final at = DateTime.utc(2026, 11, 17, 12);

    Topic? parse({Object? unsigned, Map<String, Object?>? content}) =>
        TopicParser.fromRoot(
          eventId: r'$root:example.org',
          content: content ?? {'body': 'Releases'},
          timestamp: at,
          unsigned: unsigned,
          displayName: (id) => 'Name of $id',
        );

    test('a root with a thread bundle', () {
      final topic = parse(
        unsigned: {
          'm.relations': {
            'm.thread': {
              'count': 7,
              'latest_event': {
                'sender': '@bob:example.org',
                'origin_server_ts': 1800000000000,
                'content': {'body': 'last message'},
              },
            },
          },
        },
      )!;
      expect(topic.title, 'Releases');
      expect(topic.replyCount, 7);
      expect(topic.lastSender, 'Name of @bob:example.org');
      expect(topic.lastSenderId, '@bob:example.org');
      expect(topic.lastPreview, 'last message');
      expect(topic.lastActivity.millisecondsSinceEpoch, 1800000000000);
    });

    test('a root without replies is still a topic', () {
      final topic = parse()!;
      expect(topic.replyCount, 0);
      expect(topic.lastActivity, at);
      expect(topic.lastPreview, isEmpty);
    });

    test('hostile bundles never throw and are clamped', () {
      for (final unsigned in <Object?>[
        'x',
        5,
        {'m.relations': 'x'},
        {
          'm.relations': {'m.thread': 'x'},
        },
        {
          'm.relations': {
            'm.thread': {'count': -5},
          },
        },
        {
          'm.relations': {
            'm.thread': {'count': 1e12},
          },
        },
        {
          'm.relations': {
            'm.thread': {'count': '3'},
          },
        },
        {
          'm.relations': {
            'm.thread': {'latest_event': 'x'},
          },
        },
        {
          'm.relations': {
            'm.thread': {
              'latest_event': {'sender': 5, 'content': 5},
            },
          },
        },
        {
          'm.relations': {
            'm.thread': {
              'latest_event': {
                'origin_server_ts': 'soon',
                'content': {'body': 5},
              },
            },
          },
        },
      ]) {
        final topic = parse(unsigned: unsigned);
        expect(topic, isNotNull, reason: '$unsigned');
        expect(
          topic!.replyCount,
          inInclusiveRange(0, TopicParser.replyCountMax),
        );
      }
      expect(
        parse(
          unsigned: {
            'm.relations': {
              'm.thread': {'count': -5},
            },
          },
        )!.replyCount,
        0,
      );
      expect(
        parse(
          unsigned: {
            'm.relations': {
              'm.thread': {'count': 1000000000},
            },
          },
        )!.replyCount,
        TopicParser.replyCountMax,
      );
    });

    test('the preview and the sender are bounded plain text', () {
      final topic = parse(
        unsigned: {
          'm.relations': {
            'm.thread': {
              'latest_event': {
                'sender': '@bob:example.org',
                'content': {'body': 'p' * 500},
              },
            },
          },
        },
      )!;
      expect(topic.lastPreview.characters.length, TopicParser.previewMax);
    });

    test('a bad event id is no topic', () {
      for (final id in ['', 'x', r'$', r'$a b', 'a' * 300, '\$${'a' * 300}']) {
        expect(
          TopicParser.fromRoot(eventId: id, content: {}, timestamp: at),
          isNull,
          reason: id,
        );
      }
    });
  });
}
