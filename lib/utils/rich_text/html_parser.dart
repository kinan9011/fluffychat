// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/rich_text/link_policy.dart';
import 'package:fluffychat/utils/rich_text/rich_document.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

class ParsedRichHtml {
  const ParsedRichHtml(this.document, {required this.lossy});

  final RichDocument document;

  /// True when the HTML held something the document cannot represent
  /// (images, tables, colours, nested lists...), so editing it would lose data.
  final bool lossy;
}

/// Reads `formatted_body` into a [RichDocument]. Bounded in input size, node
/// count and depth; only text, a few marks and validated links survive.
abstract class RichHtmlParser {
  static final _languageClass = RegExp(r'^language-[a-z0-9+#.\-]{1,20}$');
  static final _userPill = RegExp(
    r'^(https?://matrix\.to/#/@|matrix:u/)',
    caseSensitive: false,
  );

  /// A mention pill stays with the SDK path, which knows how to rebuild it.
  static bool _isUserPill(String href) => _userPill.hasMatch(href);

  static ParsedRichHtml? parse(String html) {
    if (html.length > RichLimits.maxParseInputUnits) return null;
    final fragment = parser.parseFragment(html);
    final state = _State();
    if (!_walk(fragment, state)) return null;
    state.finishLine();
    final document = RichDocument(state.blocks).normalized();
    final hasText = document.blocks.any((b) => b.text.trim().isNotEmpty);
    if (!hasText) return null;
    if (document.blocks.length > RichLimits.maxBlocks) return null;
    return ParsedRichHtml(document, lossy: state.lossy);
  }

  static bool _walk(dom.Node root, _State state) {
    final work = <_Work>[
      for (final child in root.nodes.reversed)
        _Work.enter(child, 1, const _Style()),
    ];
    var nodes = 0;
    while (work.isNotEmpty) {
      final item = work.removeLast();
      final exit = item.exit;
      if (exit != null) {
        exit();
        continue;
      }
      final node = item.node!;
      if (++nodes > RichLimits.maxParseNodes) return false;
      if (node is dom.Text) {
        state.addText(node.text, item.style);
        continue;
      }
      if (node is! dom.Element) continue;
      if (item.depth > RichLimits.maxParseDepth) return false;
      final name = node.localName ?? '';
      if (name == 'mx-reply') continue;
      final entered = _enter(node, name, item.style, state);
      if (entered.skipChildren) continue;
      final onExit = entered.exit;
      if (onExit != null) work.add(_Work.onExit(onExit));
      for (final child in node.nodes.reversed) {
        work.add(_Work.enter(child, item.depth + 1, entered.style));
      }
    }
    return true;
  }

  static _Entered _enter(
    dom.Element node,
    String name,
    _Style style,
    _State state,
  ) {
    switch (name) {
      case 'br':
        state.lineBreak();
        return const _Entered(skipChildren: true);
      case 'strong' || 'b':
        return _Entered(style: style.with_(InlineMark.bold));
      case 'em' || 'i':
        return _Entered(style: style.with_(InlineMark.italic));
      case 'u':
        return _Entered(style: style.with_(InlineMark.underline));
      case 'del' || 's' || 'strike':
        return _Entered(style: style.with_(InlineMark.strike));
      case 'code':
        return _Entered(style: style.with_(InlineMark.code));
      case 'pre':
        return _codeBlock(node, state);
      case 'span' || 'div':
        if (node.attributes.containsKey('data-mx-maths')) {
          return _maths(node, name, state);
        }
        if (name == 'span' && node.attributes.containsKey('data-mx-spoiler')) {
          return _Entered(style: style.with_(InlineMark.spoiler));
        }
        if (name == 'div') {
          state.finishLine();
          return _Entered(style: style, exit: state.finishLine);
        }
        if (_hasColour(node)) state.lossy = true;
        return _Entered(style: style);
      case 'a':
        final href = node.attributes['href'];
        final link = LinkPolicy.parse(href ?? '');
        if (href != null && (link == null || _isUserPill(href))) {
          state.lossy = true;
        }
        return _Entered(style: style.withLink(link));
      case 'p':
        state.finishLine();
        return _Entered(style: style, exit: state.finishLine);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        state.finishLine();
        final level = int.parse(name.substring(1));
        final saved = state.pending;
        state.pending = _Pending(BlockKind.heading, level: level);
        return _Entered(
          style: style,
          exit: () {
            state.finishLine();
            state.pending = saved;
          },
        );
      case 'blockquote':
        state.finishLine();
        final saved = state.pending;
        state.pending = const _Pending(BlockKind.quote);
        return _Entered(
          style: style,
          exit: () {
            state.finishLine();
            state.pending = saved;
          },
        );
      case 'ul' || 'ol':
        state.finishLine();
        if (state.listDepth > 0) state.lossy = true;
        state.listDepth++;
        final ordered = name == 'ol';
        final saved = state.listKind;
        state.listKind = ordered ? BlockKind.ordered : BlockKind.bullet;
        return _Entered(
          style: style,
          exit: () {
            state.finishLine();
            state.listDepth--;
            state.listKind = saved;
          },
        );
      case 'li':
        state.finishLine();
        final saved = state.pending;
        final checkbox = node.className.contains('task-list-item');
        final input = node.getElementsByTagName('input').firstOrNull;
        state.pending = checkbox
            ? _Pending(
                BlockKind.checklist,
                checked: input?.attributes['checked'] != null,
              )
            : _Pending(state.listKind ?? BlockKind.bullet);
        state.skipInputs = checkbox;
        state.liStart = !checkbox;
        return _Entered(
          style: style,
          exit: () {
            state.finishLine();
            state.pending = saved;
            state.skipInputs = false;
            state.liStart = false;
          },
        );
      case 'input':
        if (!state.skipInputs) state.lossy = true;
        return const _Entered(skipChildren: true);
      case 'img':
        state.lossy = true;
        return const _Entered(skipChildren: true);
      default:
        state.lossy = true;
        return _Entered(style: style);
    }
  }

  static bool _hasColour(dom.Element node) =>
      node.attributes.containsKey('color') ||
      node.attributes.containsKey('data-mx-color') ||
      node.attributes.containsKey('data-mx-bg-color');

  static _Entered _maths(dom.Element node, String name, _State state) {
    final tex = node.attributes['data-mx-maths'] ?? '';
    if (tex.isEmpty || tex.length > RichLimits.maxMathsUnits) {
      state.lossy = true;
      return const _Entered(skipChildren: true);
    }
    if (name != 'div') {
      state.addInline(MathsInline(tex));
      return const _Entered(skipChildren: true);
    }
    state.finishLine();
    state.blocks.add(Block(BlockKind.mathsBlock, [TextRun(tex)]));
    return const _Entered(skipChildren: true);
  }

  static _Entered _codeBlock(dom.Element node, _State state) {
    state.finishLine();
    final code =
        node.children.length == 1 && node.children.first.localName == 'code'
        ? node.children.first
        : null;
    final text = (code ?? node).text;
    String? language;
    for (final cls in (code?.className ?? '').split(' ')) {
      if (_languageClass.hasMatch(cls)) language = cls.substring(9);
    }
    state.blocks.add(
      Block(BlockKind.codeBlock, [TextRun(text)], language: language),
    );
    return const _Entered(skipChildren: true);
  }
}

class _Style {
  const _Style({this.marks = const {}, this.link});

  final Set<InlineMark> marks;
  final Uri? link;

  _Style with_(InlineMark mark) => _Style(marks: {...marks, mark}, link: link);

  _Style withLink(Uri? uri) => _Style(marks: marks, link: uri ?? link);
}

class _Pending {
  const _Pending(this.kind, {this.level = 1, this.checked = false});

  final BlockKind kind;
  final int level;
  final bool checked;
}

class _Entered {
  const _Entered({
    this.style = const _Style(),
    this.exit,
    this.skipChildren = false,
  });

  final _Style style;
  final void Function()? exit;
  final bool skipChildren;
}

class _Work {
  _Work.enter(this.node, this.depth, this.style) : exit = null;

  _Work.onExit(this.exit) : node = null, depth = 0, style = const _Style();

  final dom.Node? node;
  final int depth;
  final _Style style;
  final void Function()? exit;
}

class _State {
  final blocks = <Block>[];
  final _line = <Inline>[];
  var lossy = false;
  var listDepth = 0;
  var skipInputs = false;
  var liStart = false;
  BlockKind? listKind;
  _Pending pending = const _Pending(BlockKind.paragraph);

  void addInline(Inline inline) => _line.add(inline);

  void addText(String text, _Style style) {
    var value = text;
    if (liStart && _line.isEmpty) {
      liStart = false;
      if (pending.kind == BlockKind.bullet) {
        final trimmed = value.trimLeft();
        if (trimmed.startsWith('☐ ') || trimmed.startsWith('☑ ')) {
          pending = _Pending(
            BlockKind.checklist,
            checked: trimmed.startsWith('☑'),
          );
          value = trimmed.substring(2);
        }
      }
    }
    // Newlines between block elements ("<ul>\n<li>") are not content.
    if (_line.isEmpty) {
      if (value.contains('\n') && value.trim().isEmpty) return;
      value = value.replaceFirst(RegExp(r'^[\r\n]+'), '');
    }
    if (value.isEmpty) return;
    _line.add(TextRun(value, marks: style.marks, link: style.link));
  }

  void lineBreak() {
    if (_line.isEmpty) {
      blocks.add(const Block(BlockKind.paragraph, []));
      return;
    }
    finishLine();
  }

  void finishLine() {
    if (_line.isEmpty) return;
    blocks.add(
      Block(
        pending.kind,
        List.of(_line),
        level: pending.level,
        checked: pending.checked,
      ),
    );
    _line.clear();
  }
}
