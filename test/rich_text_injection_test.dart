// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/rich_text/link_policy.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

const corpus = [
  '<script>alert(1)</script>',
  '<img src=x onerror=alert(1)>',
  '</code></pre><script>x</script>',
  '" onmouseover="x',
  "' onfocus='x",
  '<a href="javascript:x">y</a>',
  '&lt;b&gt;',
  '<!--',
  ']]>',
  'a\u0000b',
  '<svg/onload=x>',
  '<iframe src=//evil>',
  '</span><b>',
];

const allowedElements = {
  'br',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'ul',
  'ol',
  'li',
  'pre',
  'code',
  'div',
  'span',
  'a',
  'strong',
  'em',
  'u',
  'del',
};

const allowedAttributes = {'href', 'class', 'data-mx-spoiler', 'data-mx-maths'};

String clean(String s) => s.replaceAll('\u0000', '');

void check(RichDocument doc, String needle) {
  final message = RichHtmlSerializer.serialize(doc);
  final fragment = parser.parseFragment(message.formattedBody);
  final elements = <dom.Element>[];
  void walk(dom.Node node) {
    if (node is dom.Element) elements.add(node);
    node.nodes.forEach(walk);
  }

  fragment.nodes.forEach(walk);
  for (final element in elements) {
    expect(
      allowedElements,
      contains(element.localName),
      reason: '${element.localName} in ${message.formattedBody}',
    );
    for (final name in element.attributes.keys) {
      expect(allowedAttributes, contains(name), reason: message.formattedBody);
    }
    final href = element.attributes['href'];
    if (href != null) {
      expect(LinkPolicy.parse(href), isNotNull, reason: href);
    }
    final cls = element.attributes['class'];
    if (cls != null) expect(cls, startsWith('language-'));
  }
  expect(
    fragment.text!.replaceAll('☐ ', '').replaceAll('☑ ', ''),
    contains(clean(needle).replaceAll('\r', '')),
    reason: message.formattedBody,
  );
}

void main() {
  for (final evil in corpus) {
    group('hostile text ${evil.codeUnits.take(12).toList()}', () {
      test('paragraph and every mark', () {
        check(
          RichDocument([
            Block(BlockKind.paragraph, [TextRun(evil)]),
          ]),
          evil,
        );
        for (final mark in InlineMark.values) {
          check(
            RichDocument([
              Block(BlockKind.paragraph, [
                TextRun(evil, marks: {mark}),
              ]),
            ]),
            evil,
          );
        }
      });

      test('blocks', () {
        for (final kind in BlockKind.values) {
          final doc = RichDocument([
            Block(kind, [TextRun(evil)], language: evil),
          ]);
          check(doc, evil);
        }
      });

      test('link text and label', () {
        check(
          RichDocument([
            Block(BlockKind.paragraph, [
              TextRun(evil, link: Uri.parse('https://example.org/')),
            ]),
          ]),
          evil,
        );
      });

      test('inline and block maths payload', () {
        check(
          RichDocument([
            Block(BlockKind.paragraph, [MathsInline(evil)]),
          ]),
          evil,
        );
        check(
          RichDocument([
            Block(BlockKind.mathsBlock, [TextRun(evil)]),
          ]),
          evil,
        );
      });

      test('body never contains serializer markup', () {
        final message = RichHtmlSerializer.serialize(
          RichDocument([
            Block(BlockKind.paragraph, [
              TextRun('a', marks: {InlineMark.bold}),
            ]),
          ]),
        );
        expect(message.body, isNot(contains('<strong>')));
      });
    });
  }

  test('hostile links built into the model never become anchors', () {
    for (final bad in [
      'javascript:alert(1)',
      'data:text/html,x',
      'vbscript:x',
      'file:///etc/passwd',
      'JAVASCRIPT:x',
    ]) {
      final message = RichHtmlSerializer.serialize(
        RichDocument([
          Block(BlockKind.paragraph, [TextRun('t', link: Uri.parse(bad))]),
        ]),
      );
      expect(message.formattedBody, isNot(contains('<a')), reason: bad);
    }
  });
}
