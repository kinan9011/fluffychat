// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/html_limits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

dom.Element body(String html) => parser.parse(html).body!;

void main() {
  test('deep nesting is cut past depth 40 and fast', () {
    final element = body('${'<b>' * 100000}x${'</b>' * 100000}');
    final watch = Stopwatch()..start();
    limitHtmlElements(element);
    expect(watch.elapsedMilliseconds, lessThan(3000));
    var depth = 0;
    var node = element.children.firstOrNull;
    while (node != null) {
      depth++;
      node = node.children.firstOrNull;
    }
    expect(depth, lessThanOrEqualTo(RichLimits.maxRenderDepth));
  });

  test('sibling flood keeps at most 3000 elements', () {
    final element = body('<i>x</i>' * 5000);
    limitHtmlElements(element);
    expect(element.querySelectorAll('i').length, RichLimits.maxRenderElements);
  });

  test('spoilers over 100 are masked, never shown in clear', () {
    final element = body(
      List.generate(101, (i) => '<span data-mx-spoiler>secret$i</span>').join(),
    );
    limitHtmlElements(element);
    expect(element.querySelectorAll('[data-mx-spoiler]').length, 100);
    expect(element.text, isNot(contains('secret100')));
    expect(element.text, contains('secret99'));
    expect(element.text, contains(maskSpoilerText('secret100')));
  });

  test('a spoiler inside a capped heading or maths stays masked', () {
    final heading = body(
      '<h2>t</h2>' * 100 + '<h2><span data-mx-spoiler>hid</span> ok</h2>',
    );
    limitHtmlElements(heading);
    expect(heading.text, isNot(contains('hid')));
    expect(heading.text, endsWith('${maskSpoilerText('hid')} ok'));
    final maths = body(
      '<span data-mx-maths="a"></span>' * 50 +
          '<span data-mx-maths="a" data-mx-spoiler>hid</span>',
    );
    limitHtmlElements(maths);
    expect(maths.text, isNot(contains('hid')));
  });

  test('a maths attribute on a non-span element does not skip the caps', () {
    final element = body('<b data-mx-maths="x">${'<i>x</i>' * 5000}</b>');
    limitHtmlElements(element);
    expect(element.querySelectorAll('i').length, lessThan(3000));
    final deep = body(
      '<strong data-mx-maths="x">${'<b>' * 5000}y${'</b>' * 5000}</strong>',
    );
    limitHtmlElements(deep);
    var depth = 0;
    var node = deep.children.firstOrNull;
    while (node != null) {
      depth++;
      node = node.children.firstOrNull;
    }
    expect(depth, lessThanOrEqualTo(RichLimits.maxRenderDepth));
    final spoilers = body(
      '<p data-mx-maths="x">${'<span data-mx-spoiler>s</span>' * 150}</p>',
    );
    limitHtmlElements(spoilers);
    expect(spoilers.querySelectorAll('[data-mx-spoiler]').length, 100);
    expect(
      isMathsElement(body('<b data-mx-maths="x"></b>').children.first),
      isFalse,
    );
  });

  test('headings over 100 become plain text', () {
    final element = body('<h2>t</h2>' * 101);
    limitHtmlElements(element);
    expect(element.querySelectorAll('h2').length, 100);
    expect(element.text, 't' * 101);
  });

  test('maths over 50 becomes at most 256 units of text', () {
    final element = body(
      '<span data-mx-maths="a"><code>${'z' * 400}</code></span>' * 51,
    );
    limitHtmlElements(element);
    expect(element.querySelectorAll('[data-mx-maths]').length, 50);
    expect(element.children.length, 50);
    expect(element.text.length, 50 * 400 + 256);
  });

  test('a huge maths attribute is truncated to 4096 units', () {
    final element = body('<span data-mx-maths="${'a' * 10000}"></span>');
    limitHtmlElements(element);
    expect(
      element
          .querySelector('[data-mx-maths]')!
          .attributes['data-mx-maths']!
          .length,
      RichLimits.maxRenderMathsUnits,
    );
  });

  test('normal messages are untouched', () {
    final element = body('<h1>t</h1><p>a <b>b</b></p><ul><li>c</li></ul>');
    expect(limitHtmlElements(element), 0);
  });
}
