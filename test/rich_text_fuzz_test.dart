// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/rich_text/html_parser.dart';
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

import 'rich_text_injection_test.dart' show allowedAttributes, allowedElements;
import 'utils/rich_fixtures.dart';

const _pieces = [
  '<',
  '>',
  '</',
  '/>',
  '&',
  '&amp;',
  '&#0;',
  '"',
  "'",
  '=',
  ' ',
  '\n',
  '\u0000',
  '\u202e',
  'script',
  'img',
  'a',
  'b',
  'span',
  'div',
  'href',
  'onerror',
  'javascript:',
  'data-mx-maths',
  'data-mx-spoiler',
  'x',
  '😀',
  '<!--',
  '-->',
  '<![CDATA[',
  '{{',
];

String garbage(Random random, int pieces) => List.generate(
  pieces,
  (_) => _pieces[random.nextInt(_pieces.length)],
).join();

void main() {
  test('random documents with hostile text never crash and stay bounded', () {
    final random = Random(77);
    var serialized = 0;
    for (var i = 0; i < 400; i++) {
      final base = randomDocument(random);
      final hostile = RichDocument([
        for (final block in base.blocks)
          Block(
            block.kind,
            [
              for (final inline in block.inlines)
                switch (inline) {
                  TextRun() => TextRun(
                    garbage(random, 1 + random.nextInt(6)),
                    marks: inline.marks,
                    link: inline.link,
                  ),
                  MathsInline() => MathsInline(garbage(random, 4)),
                },
            ],
            level: block.level,
            checked: block.checked,
            language: garbage(random, 1),
          ),
      ]);
      final RichMessage message;
      try {
        message = RichHtmlSerializer.serialize(hostile);
      } on RichTextTooLong {
        continue;
      }
      serialized++;
      expect(
        utf8.encode(message.formattedBody).length,
        lessThanOrEqualTo(RichLimits.maxHtmlBytes),
      );
      expect(
        utf8.encode(message.body).length,
        lessThanOrEqualTo(RichLimits.maxBodyBytes),
      );
      final fragment = parser.parseFragment(message.formattedBody);
      void walk(dom.Node node) {
        if (node is dom.Element) {
          expect(
            allowedElements,
            contains(node.localName),
            reason: message.formattedBody,
          );
          for (final name in node.attributes.keys) {
            expect(
              allowedAttributes,
              contains(name),
              reason: message.formattedBody,
            );
          }
        }
        node.nodes.forEach(walk);
      }

      fragment.nodes.forEach(walk);
      final parsed = RichHtmlParser.parse(message.formattedBody);
      if (parsed != null) {
        expect(
          parsed.document.blocks.length,
          lessThanOrEqualTo(RichLimits.maxBlocks),
        );
      }
    }
    expect(serialized, greaterThan(300));
  });

  test('oversized hostile documents are refused or bounded', () {
    final random = Random(79);
    final tooMany = RichDocument([
      for (var i = 0; i < RichLimits.maxBlocks + 1; i++)
        Block(BlockKind.paragraph, [TextRun(garbage(random, 2))]),
    ]);
    expect(
      () => RichHtmlSerializer.serialize(tooMany),
      throwsA(isA<RichTextTooLong>()),
    );
    final tooBig = RichDocument([
      for (var i = 0; i < 40; i++)
        Block(BlockKind.paragraph, [
          TextRun(
            '<&>' * 200,
            marks: const {InlineMark.bold, InlineMark.italic},
          ),
        ]),
    ]);
    expect(
      () => RichHtmlSerializer.serialize(tooBig),
      throwsA(isA<RichTextTooLong>()),
    );
  });

  test('random html garbage never crashes the parser and stays bounded', () {
    final random = Random(78);
    for (var i = 0; i < 600; i++) {
      final input = garbage(random, random.nextInt(200));
      final parsed = RichHtmlParser.parse(input);
      if (parsed == null) continue;
      expect(
        parsed.document.blocks.length,
        lessThanOrEqualTo(RichLimits.maxBlocks),
      );
      try {
        final message = RichHtmlSerializer.serialize(parsed.document);
        expect(
          utf8.encode(message.formattedBody).length,
          lessThanOrEqualTo(RichLimits.maxHtmlBytes),
        );
      } on RichTextTooLong {
        // bounded by the cap, that is the contract
      }
    }
  });

  test('a million-nesting bomb is refused quickly', () {
    final bomb = '<b>' * 100000;
    final watch = Stopwatch()..start();
    expect(RichHtmlParser.parse(bomb), isNull);
    expect(watch.elapsedMilliseconds, lessThan(3000));
  });
}
