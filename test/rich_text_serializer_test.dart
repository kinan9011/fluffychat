// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

Block para(String text, {Set<InlineMark> marks = const {}, Uri? link}) =>
    Block(BlockKind.paragraph, [TextRun(text, marks: marks, link: link)]);

RichMessage ser(List<Block> blocks) =>
    RichHtmlSerializer.serialize(RichDocument(blocks));

void main() {
  group('inline marks', () {
    test('every mark nests in the fixed order', () {
      final message = ser([
        para(
          'x',
          marks: InlineMark.values.toSet(),
          link: Uri.parse('https://example.org'),
        ),
      ]);
      expect(
        message.formattedBody,
        '<a href="https://example.org"><span data-mx-spoiler><strong><em><u>'
        '<del><code>x</code></del></u></em></strong></span></a>',
      );
    });

    test('single marks', () {
      expect(
        ser([
          para('a', marks: {InlineMark.bold}),
        ]).formattedBody,
        '<strong>a</strong>',
      );
      expect(
        ser([
          para('a', marks: {InlineMark.italic}),
        ]).formattedBody,
        '<em>a</em>',
      );
      expect(
        ser([
          para('a', marks: {InlineMark.underline}),
        ]).formattedBody,
        '<u>a</u>',
      );
      expect(
        ser([
          para('a', marks: {InlineMark.strike}),
        ]).formattedBody,
        '<del>a</del>',
      );
      expect(
        ser([
          para('a', marks: {InlineMark.code}),
        ]).formattedBody,
        '<code>a</code>',
      );
    });

    test('body fallback uses markdown-like markers, underline has none', () {
      final message = ser([
        Block(BlockKind.paragraph, [
          const TextRun('b', marks: {InlineMark.bold}),
          const TextRun(' '),
          const TextRun('i', marks: {InlineMark.italic}),
          const TextRun(' '),
          const TextRun('s', marks: {InlineMark.strike}),
          const TextRun(' '),
          const TextRun('c', marks: {InlineMark.code}),
          const TextRun(' '),
          const TextRun('u', marks: {InlineMark.underline}),
          const TextRun(' '),
          TextRun('t', link: Uri.parse('https://example.org')),
          const TextRun(' '),
          const MathsInline('x^2'),
        ]),
      ]);
      expect(
        message.body,
        '**b** *i* ~~s~~ `c` u [t](https://example.org) \$x^2\$',
      );
    });

    test('a link whose text is the url is just the url in body', () {
      final message = ser([
        para('https://example.org', link: Uri.parse('https://example.org')),
      ]);
      expect(message.body, 'https://example.org');
    });
  });

  group('spoiler', () {
    test('html carries the marker, body hides the secret', () {
      final message = ser([
        Block(BlockKind.paragraph, [
          const TextRun('the '),
          const TextRun('SECRET-42', marks: {InlineMark.spoiler}),
        ]),
      ]);
      expect(
        message.formattedBody,
        contains('<span data-mx-spoiler>SECRET-42'),
      );
      expect(message.body, 'the [spoiler]');
      expect(message.body, isNot(contains('SECRET')));
    });
  });

  group('blocks', () {
    test('consecutive paragraphs are joined by br, empty one is br', () {
      final message = ser([para('a'), para(''), para('b')]);
      expect(message.formattedBody, 'a<br><br>b');
      expect(message.body, 'a\n\nb');
    });

    test('heading levels', () {
      final message = ser([
        const Block(BlockKind.heading, [TextRun('T')], level: 2),
        para('x'),
      ]);
      expect(message.formattedBody, '<h2>T</h2>x');
      expect(message.body, '## T\nx');
    });

    test('quote lines are one blockquote', () {
      final message = ser([
        const Block(BlockKind.quote, [TextRun('a')]),
        const Block(BlockKind.quote, [TextRun('b')]),
      ]);
      expect(message.formattedBody, '<blockquote>a<br>b</blockquote>');
      expect(message.body, '> a\n> b');
    });

    test('three bullets are one list', () {
      final message = ser([
        for (final t in ['a', 'b', 'c']) Block(BlockKind.bullet, [TextRun(t)]),
      ]);
      expect(message.formattedBody, '<ul><li>a</li><li>b</li><li>c</li></ul>');
      expect(message.body, '- a\n- b\n- c');
    });

    test('ordered list numbers per group in body', () {
      final message = ser([
        const Block(BlockKind.ordered, [TextRun('a')]),
        const Block(BlockKind.ordered, [TextRun('b')]),
        para('x'),
        const Block(BlockKind.ordered, [TextRun('c')]),
      ]);
      expect(
        message.formattedBody,
        '<ol><li>a</li><li>b</li></ol>x<ol><li>c</li></ol>',
      );
      expect(message.body, '1. a\n2. b\nx\n1. c');
    });

    test('checklist uses characters, never an input element', () {
      final message = ser([
        const Block(BlockKind.checklist, [TextRun('a')]),
        const Block(BlockKind.checklist, [TextRun('b')], checked: true),
      ]);
      expect(message.formattedBody, '<ul><li>☐ a</li><li>☑ b</li></ul>');
      expect(message.formattedBody, isNot(contains('<input')));
      expect(message.body, '☐ a\n☑ b');
    });

    test('code block language is validated', () {
      expect(
        ser([
          const Block(BlockKind.codeBlock, [TextRun('a<b')], language: 'dart'),
        ]).formattedBody,
        '<pre><code class="language-dart">a&lt;b</code></pre>',
      );
      final hostile = ser([
        const Block(BlockKind.codeBlock, [
          TextRun('x'),
        ], language: 'x" onload="y'),
      ]);
      expect(hostile.formattedBody, '<pre><code>x</code></pre>');
      expect(hostile.body, '```\nx\n```');
    });

    test('maths block and inline', () {
      final message = ser([
        const Block(BlockKind.mathsBlock, [TextRun('a<b')]),
        Block(BlockKind.paragraph, const [MathsInline('x^2')]),
      ]);
      expect(
        message.formattedBody,
        '<div data-mx-maths="a&lt;b"><pre><code>a&lt;b</code></pre></div>'
        '<span data-mx-maths="x^2"><code>x^2</code></span>',
      );
      expect(message.body, '\$\$\na<b\n\$\$\n\$x^2\$');
    });
  });

  group('caps', () {
    test('501 blocks', () {
      expect(
        () => ser([for (var i = 0; i < 501; i++) para('a')]),
        throwsA(isA<RichTextTooLong>()),
      );
    });

    test('101 links', () {
      expect(
        () => ser([
          Block(BlockKind.paragraph, [
            for (var i = 0; i < 101; i++) ...[
              TextRun('a', link: Uri.parse('https://example.org')),
              const TextRun(' '),
            ],
          ]),
        ]),
        throwsA(isA<RichTextTooLong>()),
      );
    });

    test('51 maths nodes', () {
      expect(
        () => ser([
          Block(BlockKind.paragraph, [
            for (var i = 0; i < 51; i++) ...[
              const MathsInline('x'),
              const TextRun(' '),
            ],
          ]),
        ]),
        throwsA(isA<RichTextTooLong>()),
      );
    });

    test('maths of 2049 units', () {
      expect(
        () => ser([
          Block(BlockKind.paragraph, [MathsInline('x' * 2049)]),
        ]),
        throwsA(isA<RichTextTooLong>()),
      );
      expect(
        () => ser([
          Block(BlockKind.mathsBlock, [TextRun('x' * 2049)]),
        ]),
        throwsA(isA<RichTextTooLong>()),
      );
      expect(
        ser([
          Block(BlockKind.paragraph, [MathsInline('x' * 2048)]),
        ]).formattedBody,
        contains('data-mx-maths'),
      );
    });

    test('output over the byte cap', () {
      final text = '<' * (RichLimits.maxTextUnits - 1);
      expect(
        () => ser([
          para(text, marks: {InlineMark.bold}),
        ]),
        throwsA(isA<RichTextTooLong>()),
      );
    });

    test('empty document', () {
      expect(() => ser([]), throwsA(isA<RichTextTooLong>()));
      expect(() => ser([para('   ')]), throwsA(isA<RichTextTooLong>()));
    });
  });

  group('links are validated at serialization', () {
    test('a javascript link in the model is plain text, no anchor', () {
      final message = ser([
        para('click', link: Uri.parse('javascript:alert(1)')),
      ]);
      expect(message.formattedBody, 'click');
      expect(message.formattedBody, isNot(contains('<a')));
      expect(message.body, 'click');
    });

    test('data and userinfo links are dropped too', () {
      for (final bad in ['data:text/html,x', 'https://a.org@evil.org']) {
        final message = ser([para('t', link: Uri.parse(bad))]);
        expect(message.formattedBody, 't');
      }
    });

    test('href is attribute escaped', () {
      final message = ser([
        para('t', link: Uri.parse('https://example.org/?a=1&b=2')),
      ]);
      expect(
        message.formattedBody,
        contains('href="https://example.org/?a=1&amp;b=2"'),
      );
    });
  });

  group('escaping', () {
    test('text', () {
      expect(
        RichHtmlSerializer.escapeText('<a href="x">&\'</a>\u0000\r\n'),
        '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;\n',
      );
    });

    test('attribute escapes newlines too', () {
      expect(RichHtmlSerializer.escapeAttribute('a\nb"'), 'a&#10;b&quot;');
    });
  });

  group('spoiler body', () {
    test('a spoiler over mixed marks is one [spoiler] in the body', () {
      final message = ser([
        Block(BlockKind.paragraph, [
          const TextRun('a '),
          const TextRun('he', marks: {InlineMark.spoiler}),
          const TextRun('llo', marks: {InlineMark.spoiler, InlineMark.bold}),
          const TextRun(' b'),
          const TextRun('x', marks: {InlineMark.spoiler}),
        ]),
      ]);
      expect(message.body, 'a [spoiler] b[spoiler]');
      expect(message.body, isNot(contains('hello')));
    });
  });

  group('verbatim blocks', () {
    test('trailing newlines are trimmed in linear time', () {
      final watch = Stopwatch()..start();
      final doc = RichDocument([
        Block(BlockKind.codeBlock, [TextRun('${'\n' * 60000}x')]),
        Block(BlockKind.codeBlock, [TextRun('y${'\n' * 60000}')]),
      ]).normalized();
      expect(watch.elapsedMilliseconds, lessThan(100));
      expect((doc.blocks[0].inlines.single as TextRun).text.length, 60001);
      expect((doc.blocks[1].inlines.single as TextRun).text, 'y');
    });
  });
}
