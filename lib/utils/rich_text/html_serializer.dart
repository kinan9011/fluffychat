// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/rich_text/link_policy.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

class RichMessage {
  const RichMessage({required this.body, required this.formattedBody});

  final String body;
  final String formattedBody;

  /// What the homeserver gets. An edit carries body and formatted body twice
  /// (`m.new_content` and the fallback) and an encrypted event is base64.
  int eventBytes({required bool edit, required bool encrypted}) {
    final plain =
        (utf8.encode(body).length + utf8.encode(formattedBody).length) *
            (edit ? 2 : 1) +
        RichLimits.eventOverheadBytes;
    return encrypted
        ? (plain * 4 / 3).ceil() + RichLimits.encryptionOverheadBytes
        : plain;
  }
}

class RichTextTooLong implements Exception {
  const RichTextTooLong(this.reason);

  final String reason;

  @override
  String toString() => 'RichTextTooLong($reason)';
}

/// Turns a [RichDocument] into `formatted_body` HTML and a plain `body`.
/// Every user string passes through [escapeText] or [escapeAttribute]; there
/// is no input that is copied as HTML.
abstract class RichHtmlSerializer {
  static final _languagePattern = RegExp(r'^[a-z0-9+#.\-]{1,20}$');
  static final _controls = RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]');

  static String _clean(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_controls, '');

  static String escapeText(String text) => _clean(text)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String escapeAttribute(String text) =>
      escapeText(text).replaceAll('\n', '&#10;');

  static RichMessage serialize(RichDocument input) {
    final doc = input.normalized();
    _checkCaps(doc);
    final html = StringBuffer();
    final body = StringBuffer();
    var index = 0;
    var firstLine = true;
    var previousParagraph = false;
    var previousEmpty = false;
    while (index < doc.blocks.length) {
      final block = doc.blocks[index];
      var end = index + 1;
      if (_groupable(block.kind)) {
        while (end < doc.blocks.length && doc.blocks[end].kind == block.kind) {
          end++;
        }
      }
      final group = doc.blocks.sublist(index, end);
      final paragraph = block.kind == BlockKind.paragraph;
      if (!firstLine) {
        body.write('\n');
        final blankBeforeBlock =
            !paragraph && previousParagraph && previousEmpty;
        if (paragraph && previousParagraph || blankBeforeBlock) {
          html.write('<br>');
        }
      }
      html.write(_groupHtml(block.kind, group));
      body.write(_groupBody(block.kind, group));
      previousParagraph = paragraph;
      previousEmpty = paragraph && block.inlines.isEmpty;
      firstLine = false;
      index = end;
    }
    final formatted = html.toString();
    final plain = body.toString();
    if (plain.trim().isEmpty) throw const RichTextTooLong('empty');
    if (utf8.encode(formatted).length > RichLimits.maxHtmlBytes ||
        utf8.encode(plain).length > RichLimits.maxBodyBytes) {
      throw const RichTextTooLong('bytes');
    }
    return RichMessage(body: plain, formattedBody: formatted);
  }

  static bool _groupable(BlockKind kind) => switch (kind) {
    BlockKind.quote ||
    BlockKind.bullet ||
    BlockKind.ordered ||
    BlockKind.checklist => true,
    _ => false,
  };

  static void _checkCaps(RichDocument doc) {
    if (doc.blocks.length > RichLimits.maxBlocks) {
      throw const RichTextTooLong('blocks');
    }
    var units = 0;
    var links = 0;
    var maths = 0;
    for (final block in doc.blocks) {
      if (block.kind == BlockKind.mathsBlock) {
        maths++;
        if (block.text.length > RichLimits.maxMathsUnits) {
          throw const RichTextTooLong('maths');
        }
      }
      for (final inline in block.inlines) {
        switch (inline) {
          case TextRun():
            units += inline.text.length;
            if (inline.link != null) links++;
          case MathsInline():
            maths++;
            units += inline.tex.length;
            if (inline.tex.length > RichLimits.maxMathsUnits) {
              throw const RichTextTooLong('maths');
            }
        }
      }
    }
    if (units > RichLimits.maxTextUnits) throw const RichTextTooLong('text');
    if (links > RichLimits.maxLinks) throw const RichTextTooLong('links');
    if (maths > RichLimits.maxMaths) throw const RichTextTooLong('maths');
  }

  static Uri? _safeLink(Uri? link) =>
      link == null ? null : LinkPolicy.parse(link.toString());

  static String _mathsPayload(String tex) => _clean(tex).trim();

  static String _inlineHtml(Inline inline) {
    switch (inline) {
      case MathsInline():
        final tex = _mathsPayload(inline.tex);
        if (tex.isEmpty) return '';
        return '<span data-mx-maths="${escapeAttribute(tex)}">'
            '<code>${escapeText(tex)}</code></span>';
      case TextRun():
        final lines = _clean(inline.text).split('\n');
        var out = lines.map(escapeText).join('<br>');
        if (inline.marks.contains(InlineMark.code)) out = '<code>$out</code>';
        if (inline.marks.contains(InlineMark.strike)) out = '<del>$out</del>';
        if (inline.marks.contains(InlineMark.underline)) out = '<u>$out</u>';
        if (inline.marks.contains(InlineMark.italic)) out = '<em>$out</em>';
        if (inline.marks.contains(InlineMark.bold)) {
          out = '<strong>$out</strong>';
        }
        if (inline.marks.contains(InlineMark.spoiler)) {
          out = '<span data-mx-spoiler>$out</span>';
        }
        final link = _safeLink(inline.link);
        if (link != null) {
          out = '<a href="${escapeAttribute(link.toString())}">$out</a>';
        }
        return out;
    }
  }

  static String _inlines(Block block) => block.inlines.map(_inlineHtml).join();

  static String _groupHtml(BlockKind kind, List<Block> group) {
    switch (kind) {
      case BlockKind.paragraph:
        return _inlines(group.single);
      case BlockKind.heading:
        final level = group.single.level.clamp(1, 6);
        return '<h$level>${_inlines(group.single)}</h$level>';
      case BlockKind.quote:
        return '<blockquote>${group.map(_inlines).join('<br>')}</blockquote>';
      case BlockKind.bullet:
        return '<ul>${group.map((b) => '<li>${_inlines(b)}</li>').join()}</ul>';
      case BlockKind.ordered:
        return '<ol>${group.map((b) => '<li>${_inlines(b)}</li>').join()}</ol>';
      case BlockKind.checklist:
        return '<ul>${group.map((b) => '<li>${b.checked ? '☑' : '☐'} ${_inlines(b)}</li>').join()}</ul>';
      case BlockKind.codeBlock:
        final language = group.single.language?.toLowerCase();
        final attribute =
            language != null && _languagePattern.hasMatch(language)
            ? ' class="language-$language"'
            : '';
        return '<pre><code$attribute>${escapeText(group.single.text)}</code></pre>';
      case BlockKind.mathsBlock:
        final tex = _mathsPayload(group.single.text);
        return '<div data-mx-maths="${escapeAttribute(tex)}">'
            '<pre><code>${escapeText(tex)}</code></pre></div>';
    }
  }

  static String _inlineBody(Inline inline) {
    switch (inline) {
      case MathsInline():
        final tex = _mathsPayload(inline.tex);
        return tex.isEmpty ? '' : '\$$tex\$';
      case TextRun():
        if (inline.marks.contains(InlineMark.spoiler)) return '[spoiler]';
        var out = _clean(inline.text);
        if (out.isEmpty) return out;
        if (inline.marks.contains(InlineMark.code)) out = '`$out`';
        if (inline.marks.contains(InlineMark.strike)) out = '~~$out~~';
        if (inline.marks.contains(InlineMark.italic)) out = '*$out*';
        if (inline.marks.contains(InlineMark.bold)) out = '**$out**';
        final link = _safeLink(inline.link);
        if (link != null && link.toString() != inline.text) {
          out = '[$out]($link)';
        }
        return out;
    }
  }

  static String _inlinesBody(Block block) {
    final out = StringBuffer();
    var inSpoiler = false;
    for (final inline in block.inlines) {
      final spoiler =
          inline is TextRun && inline.marks.contains(InlineMark.spoiler);
      if (!(spoiler && inSpoiler)) out.write(_inlineBody(inline));
      inSpoiler = spoiler;
    }
    return out.toString();
  }

  static String _groupBody(BlockKind kind, List<Block> group) {
    switch (kind) {
      case BlockKind.paragraph:
        return _inlinesBody(group.single);
      case BlockKind.heading:
        return '${'#' * group.single.level.clamp(1, 6)} ${_inlinesBody(group.single)}';
      case BlockKind.quote:
        return group.map((b) => '> ${_inlinesBody(b)}').join('\n');
      case BlockKind.bullet:
        return group.map((b) => '- ${_inlinesBody(b)}').join('\n');
      case BlockKind.ordered:
        return [
          for (var i = 0; i < group.length; i++)
            '${i + 1}. ${_inlinesBody(group[i])}',
        ].join('\n');
      case BlockKind.checklist:
        return group
            .map((b) => '${b.checked ? '☑' : '☐'} ${_inlinesBody(b)}')
            .join('\n');
      case BlockKind.codeBlock:
        final language = group.single.language?.toLowerCase();
        final tag = language != null && _languagePattern.hasMatch(language)
            ? language
            : '';
        return '```$tag\n${_clean(group.single.text)}\n```';
      case BlockKind.mathsBlock:
        return '\$\$\n${_mathsPayload(group.single.text)}\n\$\$';
    }
  }
}
