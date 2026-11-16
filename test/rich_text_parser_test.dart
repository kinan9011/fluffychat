// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/rich_text/html_parser.dart';
import 'package:fluffychat/utils/rich_text/html_serializer.dart';
import 'package:fluffychat/utils/rich_text/rich_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/rich_fixtures.dart';

void main() {
  group('round trip', () {
    test('200 seeded random documents', () {
      final random = Random(5);
      var checked = 0;
      for (var i = 0; i < 200; i++) {
        final doc = randomDocument(random).normalized();
        if (!doc.blocks.any((b) => b.text.trim().isNotEmpty)) continue;
        final RichMessage message;
        try {
          message = RichHtmlSerializer.serialize(doc);
        } on RichTextTooLong {
          continue;
        }
        final parsed = RichHtmlParser.parse(message.formattedBody);
        expect(parsed, isNotNull, reason: message.formattedBody);
        expect(parsed!.lossy, isFalse, reason: message.formattedBody);
        expect(
          parsed.document.normalized(),
          doc,
          reason: message.formattedBody,
        );
        checked++;
      }
      expect(checked, greaterThan(150));
    });

    test('a blank line between a paragraph and a list survives', () {
      final doc = RichDocument([
        const Block(BlockKind.paragraph, [TextRun('a')]),
        const Block(BlockKind.paragraph, []),
        const Block(BlockKind.bullet, [TextRun('b')]),
      ]);
      final html = RichHtmlSerializer.serialize(doc).formattedBody;
      expect(RichHtmlParser.parse(html)!.document, doc);
    });
  });

  group('foreign html', () {
    test('paragraphs become blocks', () {
      final parsed = RichHtmlParser.parse('<p>a</p><p>b</p>')!;
      expect(parsed.document.blocks.map((b) => b.text), ['a', 'b']);
      expect(parsed.lossy, isFalse);
    });

    test('a javascript link keeps its text only', () {
      final parsed = RichHtmlParser.parse('<a href="javascript:x">t</a>')!;
      final run = parsed.document.blocks.single.inlines.single as TextRun;
      expect(run.text, 't');
      expect(run.link, isNull);
    });

    test('images, colours and tables are lossy', () {
      expect(RichHtmlParser.parse('x<img src="mxc://a/b">')!.lossy, isTrue);
      expect(RichHtmlParser.parse('<font color="red">x</font>')!.lossy, isTrue);
      expect(
        RichHtmlParser.parse('<table><tr><td>x</td></tr></table>')!.lossy,
        isTrue,
      );
      expect(
        RichHtmlParser.parse('<ul><li>a<ul><li>b</li></ul></li></ul>')!.lossy,
        isTrue,
      );
    });

    test('mx-reply is dropped', () {
      final parsed = RichHtmlParser.parse(
        '<mx-reply><blockquote>old</blockquote></mx-reply>x',
      )!;
      expect(parsed.document.plainText, 'x');
    });

    test('github style checkbox list', () {
      final parsed = RichHtmlParser.parse(
        '<ul><li class="task-list-item"><input type="checkbox" checked>a</li>'
        '<li class="task-list-item"><input type="checkbox">b</li></ul>',
      )!;
      expect(parsed.document.blocks.map((b) => b.kind), [
        BlockKind.checklist,
        BlockKind.checklist,
      ]);
      expect(parsed.document.blocks.map((b) => b.checked), [true, false]);
    });

    test('unknown tags keep their text', () {
      final parsed = RichHtmlParser.parse('<blink>t</blink>')!;
      expect(parsed.document.plainText, 't');
      expect(parsed.lossy, isTrue);
    });

    test('only href, language class and maths survive as attributes', () {
      final parsed = RichHtmlParser.parse(
        '<span onclick="x" data-mx-maths="a+b"><code>q</code></span>',
      )!;
      expect(
        parsed.document.blocks.single.inlines.single,
        const MathsInline('a+b'),
      );
    });
  });

  group('markdown renderer output', () {
    test('newlines between blocks are not content', () {
      final parsed = RichHtmlParser.parse(
        '<p>a</p>\n<ul>\n<li>x</li>\n<li>y</li>\n</ul>\n<p>b</p>',
      )!;
      expect(parsed.document.blocks.map((b) => (b.kind, b.text)), [
        (BlockKind.paragraph, 'a'),
        (BlockKind.bullet, 'x'),
        (BlockKind.bullet, 'y'),
        (BlockKind.paragraph, 'b'),
      ]);
      expect(parsed.lossy, isFalse);
    });

    test('a break followed by a newline is one line break', () {
      final parsed = RichHtmlParser.parse('a<br />\nb')!;
      expect(parsed.document.blocks.map((b) => b.text), ['a', 'b']);
    });

    test('a rejected href makes the document lossy', () {
      expect(
        RichHtmlParser.parse('<a href="ftp://x.org">t</a>')!.lossy,
        isTrue,
      );
      expect(
        RichHtmlParser.parse('<a href="https://x.org">t</a>')!.lossy,
        isFalse,
      );
    });
  });

  group('bounds', () {
    test('depth 21 is refused, 20 is fine', () {
      String nest(int n) => '${'<b>' * n}x${'</b>' * n}';
      expect(RichHtmlParser.parse(nest(21)), isNull);
      expect(RichHtmlParser.parse(nest(20)), isNotNull);
    });

    test('2001 nodes are refused', () {
      expect(RichHtmlParser.parse('<b>x</b>' * 1001), isNull);
      expect(RichHtmlParser.parse('<b>x</b>' * 600), isNotNull);
    });

    test('input over the unit cap is refused', () {
      expect(
        RichHtmlParser.parse('a' * (RichLimits.maxParseInputUnits + 1)),
        isNull,
      );
    });

    test('maths over the cap is skipped and lossy', () {
      final parsed = RichHtmlParser.parse(
        'x<span data-mx-maths="${'a' * (RichLimits.maxMathsUnits + 1)}"></span>',
      )!;
      expect(parsed.lossy, isTrue);
      expect(parsed.document.plainText, 'x');
    });

    test('no text means null', () {
      expect(RichHtmlParser.parse(''), isNull);
      expect(RichHtmlParser.parse('<b></b>'), isNull);
    });
  });
}
