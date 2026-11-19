// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/rich_text/editor_text.dart';
import 'package:odango/utils/rich_text/format_range.dart';
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

import 'utils/rich_fixtures.dart';

RichDocument build(String text, [List<FormatRange> ranges = const []]) =>
    RichEditorText.build(text, ranges).normalized();

void main() {
  group('build line prefixes', () {
    test('every block prefix', () {
      final doc = build(
        '# h1\n###### h6\n> q\n- b\n1. o\n2. p\n☐ c\n☑ d\nplain',
      );
      expect(doc.blocks.map((b) => b.kind), [
        BlockKind.heading,
        BlockKind.heading,
        BlockKind.quote,
        BlockKind.bullet,
        BlockKind.ordered,
        BlockKind.ordered,
        BlockKind.checklist,
        BlockKind.checklist,
        BlockKind.paragraph,
      ]);
      expect(doc.blocks[0].level, 1);
      expect(doc.blocks[1].level, 6);
      expect(doc.blocks[6].checked, isFalse);
      expect(doc.blocks[7].checked, isTrue);
      expect(doc.blocks.map((b) => b.text), [
        'h1',
        'h6',
        'q',
        'b',
        'o',
        'p',
        'c',
        'd',
        'plain',
      ]);
    });

    test('seven hashes and a missing space are plain text', () {
      expect(build('####### x').blocks.single.kind, BlockKind.paragraph);
      expect(build('#x').blocks.single.kind, BlockKind.paragraph);
      expect(build('-x').blocks.single.kind, BlockKind.paragraph);
    });

    test('code fence open, closed, with language and unclosed', () {
      final closed = build('a\n```dart\nx\n# y\n```\nb');
      expect(closed.blocks.map((b) => b.kind), [
        BlockKind.paragraph,
        BlockKind.codeBlock,
        BlockKind.paragraph,
      ]);
      expect(closed.blocks[1].text, 'x\n# y');
      expect(closed.blocks[1].language, 'dart');
      final unclosed = build('```\nx\ny');
      expect(unclosed.blocks.single.text, 'x\ny');
      expect(build('```bad lang!\nx\n```').blocks.single.language, isNull);
    });

    test('maths fences and the one line form', () {
      final fenced = build('\$\$\na+b\n\$\$');
      expect(fenced.blocks.single.kind, BlockKind.mathsBlock);
      expect(fenced.blocks.single.text, 'a+b');
      final one = build('\$\$a+b\$\$');
      expect(one.blocks.single.text, 'a+b');
      expect(
        build('\$\$\n- not a list\n\$\$').blocks.single.text,
        '- not a list',
      );
    });

    test('prefixes stay literal inside a fence', () {
      expect(build('```\n> q\n```').blocks.single.text, '> q');
    });
  });

  group('build ranges', () {
    test('ranges are clipped after the prefix', () {
      final doc = build('# abc', const [FormatRange(0, 5, RangeKind.bold)]);
      final run = doc.blocks.single.inlines.single as TextRun;
      expect(run.text, 'abc');
      expect(run.marks, {InlineMark.bold});
    });

    test('a range spanning two lines splits per line', () {
      final doc = build('ab\ncd', const [FormatRange(1, 4, RangeKind.italic)]);
      final first = doc.blocks[0].inlines;
      expect(first, const [
        TextRun('a'),
        TextRun('b', marks: {InlineMark.italic}),
      ]);
      expect(doc.blocks[1].inlines, const [
        TextRun('c', marks: {InlineMark.italic}),
        TextRun('d'),
      ]);
    });

    test('overlapping bold and italic become a set', () {
      final doc = build('abcd', const [
        FormatRange(0, 3, RangeKind.bold),
        FormatRange(1, 4, RangeKind.italic),
      ]);
      expect(doc.blocks.single.inlines, const [
        TextRun('a', marks: {InlineMark.bold}),
        TextRun('bc', marks: {InlineMark.bold, InlineMark.italic}),
        TextRun('d', marks: {InlineMark.italic}),
      ]);
    });

    test('maths wins over other marks inside it', () {
      final doc = build('x ab y', const [
        FormatRange(2, 4, RangeKind.maths),
        FormatRange(0, 6, RangeKind.bold),
      ]);
      final inlines = doc.blocks.single.inlines;
      expect(inlines[1], const MathsInline('ab'));
    });

    test('link ranges set the link', () {
      final doc = build('go', [
        FormatRange(
          0,
          2,
          RangeKind.link,
          link: Uri.parse('https://example.org'),
        ),
      ]);
      expect(
        (doc.blocks.single.inlines.single as TextRun).link,
        Uri.parse('https://example.org'),
      );
    });
  });

  group('a spoiler never loses its cover to maths or a fenced block', () {
    const secret = 'SECRET-42';

    void expectHidden(String text, int from, int to) {
      final doc = RichEditorText.build(text, [
        FormatRange(from, to, RangeKind.spoiler),
      ]);
      final message = RichHtmlSerializer.serialize(doc);
      expect(message.body, isNot(contains(secret)));
      expect(message.body, contains('[spoiler]'));
      expect(
        message.formattedBody,
        contains('<span data-mx-spoiler>'),
        reason: message.formattedBody,
      );
    }

    test('inline maths under a spoiler', () {
      const text = 'a $secret b';
      final doc = RichEditorText.build(text, [
        const FormatRange(2, 11, RangeKind.maths),
        const FormatRange(0, 13, RangeKind.spoiler),
      ]);
      final message = RichHtmlSerializer.serialize(doc);
      expect(message.body, isNot(contains(secret)));
    });

    test('a fenced code block', () {
      const text = '```\n$secret\n```';
      expectHidden(text, 4, 13);
    });

    test('a fenced maths block', () {
      const text = '\$\$\n$secret\n\$\$';
      expectHidden(text, 3, 12);
    });

    test('the one line maths form', () {
      const text = '\$\$$secret\$\$';
      expectHidden(text, 0, text.length);
    });

    test('an unclosed fence', () {
      const text = '```\nline\n$secret';
      expectHidden(text, 10, 19);
    });

    test('a spoiler elsewhere leaves the block alone', () {
      final doc = RichEditorText.build('```\ncode\n```\nplain secret', [
        const FormatRange(15, 21, RangeKind.spoiler),
      ]);
      expect(doc.blocks.first.kind, BlockKind.codeBlock);
    });
  });

  group('analyze', () {
    test('classifies every line like build does', () {
      final lines = RichEditorText.analyze(
        '# a\n> b\n- c\n1. d\n☐ e\n```dart\nx\n# y\n```\n\$\$\nz\n\$\$\n\$\$w\$\$\nplain',
      );
      expect(lines.map((l) => l.kind), [
        LineKind.heading,
        LineKind.quote,
        LineKind.bullet,
        LineKind.ordered,
        LineKind.checklist,
        LineKind.fence,
        LineKind.codeBody,
        LineKind.codeBody,
        LineKind.fence,
        LineKind.fence,
        LineKind.mathsBody,
        LineKind.fence,
        LineKind.mathsBody,
        LineKind.paragraph,
      ]);
      expect(lines.first.prefixLength, 2);
      expect(lines[3].prefixLength, 3);
      expect(lines.first.start, 0);
      expect(lines.last.end, lines.last.start + 'plain'.length);
    });

    test('block kinds agree with build over seeded documents', () {
      final random = Random(21);
      for (var i = 0; i < 100; i++) {
        final doc = randomDocument(random, safeStart: true).normalized();
        final editor = RichEditorText.render(doc);
        final blockLines = RichEditorText.analyze(editor.text)
            .where(
              (l) => switch (l.kind) {
                LineKind.fence ||
                LineKind.codeBody ||
                LineKind.mathsBody => false,
                _ => true,
              },
            )
            .length;
        final verbatim = doc.blocks.where((b) => b.isVerbatim).length;
        expect(blockLines, doc.blocks.length - verbatim, reason: editor.text);
      }
    });
  });

  group('render', () {
    test('ordered lists are renumbered per group', () {
      final editor = RichEditorText.render(
        const RichDocument([
          Block(BlockKind.ordered, [TextRun('a')]),
          Block(BlockKind.ordered, [TextRun('b')]),
          Block(BlockKind.paragraph, [TextRun('x')]),
          Block(BlockKind.ordered, [TextRun('c')]),
        ]),
      );
      expect(editor.text, '1. a\n2. b\nx\n1. c');
    });

    test('a paragraph that looks like a prefix does not round trip', () {
      expect(
        RichEditorText.roundTrips(
          const RichDocument([
            Block(BlockKind.paragraph, [TextRun('- not a list')]),
          ]),
        ),
        isFalse,
      );
      expect(
        RichEditorText.roundTrips(
          const RichDocument([
            Block(BlockKind.paragraph, [TextRun('fine')]),
          ]),
        ),
        isTrue,
      );
    });

    test('300 seeded random documents round trip', () {
      final random = Random(11);
      for (var i = 0; i < 300; i++) {
        final doc = randomDocument(random, safeStart: true).normalized();
        final editor = RichEditorText.render(doc);
        expect(
          RichEditorText.build(editor.text, editor.ranges).normalized(),
          doc,
          reason: editor.text,
        );
      }
    });
  });
}
