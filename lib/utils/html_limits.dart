// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:html/dom.dart' as dom;
import 'package:odango/config/design_constants.dart';

const _headings = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

const _spoilerMask = '\u2588';
const _spoilerMaskUnits = 2000;

/// Same predicate for the cap and the renderer, so neither can disagree about
/// which elements are maths and which subtrees are skipped.
bool isMathsElement(dom.Element element) =>
    element.attributes.containsKey('data-mx-maths') &&
    (element.localName == 'span' || element.localName == 'div');

/// Visible stand-in for spoiler text: same word shape, no content.
String maskSpoilerText(String text) =>
    (text.length > _spoilerMaskUnits
            ? text.substring(0, _spoilerMaskUnits)
            : text)
        .replaceAll(RegExp(r'\S'), _spoilerMask);

String _textOf(dom.Element root, {required int max}) {
  final buffer = StringBuffer();
  var length = 0;
  final stack = <(dom.Node, bool)>[(root, false)];
  while (stack.isNotEmpty && length < max) {
    final (node, hidden) = stack.removeLast();
    if (node is dom.Text) {
      final text = hidden ? maskSpoilerText(node.data) : node.data;
      buffer.write(text);
      length += text.length;
      continue;
    }
    if (node is! dom.Element) continue;
    final nowHidden = hidden || node.attributes.containsKey('data-mx-spoiler');
    for (final child in node.nodes.reversed) {
      stack.add((child, nowHidden));
    }
  }
  final text = buffer.toString();
  return text.length > max ? text.substring(0, max) : text;
}

/// The formatted body of someone else's message, or null when it is longer
/// than any client of this app sends: parsing is the expensive part, so an
/// over-long one is shown as its plain body instead.
String? capHtmlInput(String? html) =>
    html != null && html.length > RichLimits.maxRenderInputUnits ? null : html;

/// Caps what an incoming formatted message can ask the renderer to build:
/// element count, nesting, headings, spoilers and maths. Runs iteratively, so
/// a hostile nesting cannot overflow the stack. Elements cut down to text keep
/// every spoiler inside them masked. Returns the number of changes.
int limitHtmlElements(dom.Element body) {
  final removals = <dom.Element>[];
  final replacements = <(dom.Element, String)>[];
  var elements = 0;
  var headings = 0;
  var spoilers = 0;
  var maths = 0;
  var changes = 0;
  final stack = <(dom.Element, int)>[];
  for (final child in body.children.reversed) {
    stack.add((child, 1));
  }
  while (stack.isNotEmpty) {
    final (element, depth) = stack.removeLast();
    if (elements >= RichLimits.maxRenderElements ||
        depth > RichLimits.maxRenderDepth) {
      removals.add(element);
      continue;
    }
    elements++;
    final name = element.localName ?? '';
    if (element.attributes.containsKey('data-mx-spoiler') &&
        ++spoilers > RichLimits.maxRenderSpoilers) {
      replacements.add((element, _textOf(element, max: 1 << 30)));
      continue;
    }
    if (isMathsElement(element)) {
      if (++maths > RichLimits.maxRenderMaths) {
        replacements.add((element, _textOf(element, max: 256)));
        continue;
      }
      final tex = element.attributes['data-mx-maths']!;
      if (tex.length > RichLimits.maxRenderMathsUnits) {
        element.attributes['data-mx-maths'] = tex.substring(
          0,
          RichLimits.maxRenderMathsUnits,
        );
        changes++;
      }
      continue;
    }
    if (_headings.contains(name) && ++headings > RichLimits.maxRenderHeadings) {
      replacements.add((element, _textOf(element, max: 1 << 30)));
      continue;
    }
    for (final child in element.children.reversed) {
      stack.add((child, depth + 1));
    }
  }
  for (final element in removals) {
    element.remove();
  }
  for (final (element, text) in replacements) {
    element.replaceWith(dom.Text(text));
  }
  return changes + removals.length + replacements.length;
}
