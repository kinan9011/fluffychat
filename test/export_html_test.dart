// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/export/export_html.dart';
import 'package:fluffychat/utils/export/export_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _payloads = <String>[
  '<script>alert(1)</script>',
  '"><img src=x onerror=alert(1)>',
  "'><svg/onload=alert(1)>",
  'javascript:alert(1)',
  '<a href="javascript:alert(1)">x</a>',
  '</div><script>x</script>',
  '`<b>`',
  '&lt;script&gt;',
  '<style>body{display:none}</style>',
  '<iframe src="https://evil.example"></iframe>',
  '<meta http-equiv="refresh" content="0;url=https://evil.example">',
];

ExportEvent _event({
  String id = r'$e1',
  String name = 'Alice',
  String sender = '@alice:example.org',
  String text = 'hello',
  String? mediaName,
  DateTime? time,
}) => ExportEvent(
  eventId: id,
  senderId: sender,
  senderName: name,
  time: time ?? DateTime.utc(2030, 5, 10, 12, 30),
  type: 'm.room.message',
  text: text,
  content: const {},
  mediaName: mediaName,
);

class _PoisonEvent extends ExportEvent {
  _PoisonEvent()
    : super(
        eventId: r'$p',
        senderId: '@a:b',
        senderName: 'A',
        time: DateTime.utc(2030),
        type: 'm.room.message',
        text: '',
        content: const {},
      );

  @override
  String get text => throw StateError('read after the limit');
}

ExportMeta _meta({
  String name = 'Room',
  String? topic,
  bool truncated = false,
}) => ExportMeta(
  roomId: '!room:example.org',
  roomName: name,
  topic: topic,
  encrypted: false,
  exportedAt: DateTime.utc(2030, 5, 11),
  truncated: truncated,
);

final _tagName = RegExp(r'<(/?)([A-Za-z!][A-Za-z0-9-]*)');

Set<String> _tags(String html) => {
  for (final match in _tagName.allMatches(html))
    '${match.group(1)}${match.group(2)!.toLowerCase()}',
};

const _allowed = {
  '!doctype',
  'html',
  '/html',
  'head',
  '/head',
  'meta',
  'title',
  '/title',
  'style',
  '/style',
  'body',
  '/body',
  'h1',
  '/h1',
  'p',
  '/p',
  'div',
  '/div',
  'span',
  '/span',
  'a',
  '/a',
  'br',
};

void main() {
  group('esc', () {
    test('the five markup characters and the backtick are escaped', () {
      expect(esc('<>&"\'`'), '&lt;&gt;&amp;&quot;&#39;&#96;');
    });

    test('an entity is escaped, not interpreted', () {
      expect(esc('&lt;'), '&amp;lt;');
    });

    test('control, zero width and bidi override characters are dropped', () {
      expect(esc('a\u0000b\u0007c\u202Ed\u2066e\u200Ff\uFEFFg'), 'abcdefg');
    });

    test('newline and tab survive, other text is untouched', () {
      expect(esc('a\nb\tc é 😀 مرحبا'), 'a\nb\tc é 😀 مرحبا');
    });
  });

  group('buildHtml with hostile content', () {
    for (final payload in _payloads) {
      test('every dynamic field is inert: $payload', () {
        final html = buildHtml(
          _meta(name: payload, topic: payload),
          [
            _event(
              name: payload,
              sender: payload,
              text: payload,
              mediaName: payload,
            ),
          ],
          mediaPaths: {0: 'media/000001-file'},
        );
        expect(_tags(html).difference(_allowed), isEmpty, reason: html);
        expect(html, isNot(contains('<script')));
        expect(html, isNot(contains('<img')));
        expect(html, isNot(contains('<svg')));
        expect(html, isNot(contains('<iframe')));
        expect(RegExp(r'<[^>]*\son\w+=').hasMatch(html), isFalse);
        expect(html, isNot(contains('href="javascript')));
        expect(RegExp(r'<[^>]*javascript:').hasMatch(html), isFalse);
        expect(RegExp(r'<a ').allMatches(html), hasLength(1));
      });
    }

    test('a name that tries to leave an attribute stays text', () {
      final html = buildHtml(
        _meta(),
        [_event(mediaName: '" onmouseover="alert(1)')],
        mediaPaths: {0: 'media/000001-x'},
      );
      expect(html, isNot(contains('" onmouseover=')));
      expect(html, contains('&quot; onmouseover=&quot;alert(1)'));
    });

    test('the media link comes from the generated path only', () {
      final html = buildHtml(
        _meta(),
        [
          _event(
            text: 'see https://example.org/x',
            mediaName: '../../etc/passwd',
          ),
        ],
        mediaPaths: {0: 'media/000001-passwd'},
      );
      expect(html, contains('href="media/000001-passwd"'));
      expect(html, isNot(contains('href="https://')));
      expect(html, isNot(contains('href="../')));
    });

    test('a message without a generated path gets no link', () {
      final html = buildHtml(_meta(), [_event(mediaName: 'a.png')]);
      expect(RegExp(r'<a ').allMatches(html), isEmpty);
    });

    test('urls in text are not turned into links', () {
      final html = buildHtml(_meta(), [_event(text: 'https://example.org')]);
      expect(RegExp(r'<a ').allMatches(html), isEmpty);
      expect(html, contains('https://example.org'));
    });

    test('a script, remote style or image is forbidden by the page itself', () {
      final html = buildHtml(_meta(), [_event()]);
      expect(
        html,
        contains(
          "default-src 'none'; style-src 'unsafe-inline'; img-src 'none'",
        ),
      );
    });

    test('formatted_body is never exported', () {
      final event = ExportEvent(
        eventId: r'$e1',
        senderId: '@a:b',
        senderName: 'A',
        time: DateTime.utc(2030),
        type: 'm.room.message',
        text: 'plain body',
        content: const {
          'body': 'plain body',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<b>formatted</b><script>x</script>',
        },
      );
      final html = buildHtml(_meta(), [event]);
      expect(html, contains('plain body'));
      expect(html, isNot(contains('formatted')));
      expect(html, isNot(contains('<b>')));
    });

    test('line breaks become br after escaping', () {
      final html = buildHtml(_meta(), [_event(text: '<i>a</i>\nb')]);
      expect(html, contains('&lt;i&gt;a&lt;/i&gt;<br>b'));
    });

    test('a megabyte on one line is cut', () {
      final html = buildHtml(_meta(), [_event(text: 'x' * 1000000)]);
      expect(html.length, lessThan(ExportLimits.maxTextPerMessage + 5000));
    });

    test('text direction is left to the reader', () {
      final html = buildHtml(_meta(), [_event(text: 'مرحبا')]);
      expect(html, contains('dir="auto"'));
      expect(html, contains('مرحبا'));
    });

    test('truncated and skipped-media notes are escaped text', () {
      final html = buildHtml(
        _meta(truncated: true),
        [_event()],
        truncatedNote: '<b>stopped</b>',
        mediaSkippedNote: '<i>skipped</i>',
      );
      expect(html, isNot(contains('<b>stopped')));
      expect(html, contains('&lt;b&gt;stopped'));
      expect(html, contains('&lt;i&gt;skipped'));
    });

    test('the time is a fixed UTC format', () {
      final html = buildHtml(_meta(), [_event()]);
      expect(html, contains('2030-05-10 12:30 UTC'));
    });
  });

  group('length limit', () {
    test('stops at the limit without reading the rest', () {
      final events = [
        _event(id: r'$1', text: 'x' * 2000),
        _event(id: r'$2', text: 'y' * 2000),
        _PoisonEvent(),
      ];
      expect(
        () => buildHtml(_meta(), events, maxLength: 3000),
        throwsA(isA<ExportTooLarge>()),
      );
    });

    test('a page under the limit is built', () {
      expect(
        buildHtml(_meta(), [_event()], maxLength: 100000),
        contains('hello'),
      );
    });
  });
}
