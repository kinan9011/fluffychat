// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/rich_document.dart';
import 'package:flutter/foundation.dart';

enum LineKind {
  paragraph,
  heading,
  quote,
  bullet,
  ordered,
  checklist,
  fence,
  codeBody,
  mathsBody,
}

@immutable
class LineInfo {
  const LineInfo({
    required this.start,
    required this.end,
    required this.kind,
    this.prefixLength = 0,
    this.level = 1,
  });

  final int start;
  final int end;
  final LineKind kind;
  final int prefixLength;
  final int level;

  bool get isBlock => switch (kind) {
    LineKind.heading ||
    LineKind.quote ||
    LineKind.bullet ||
    LineKind.ordered ||
    LineKind.checklist => true,
    _ => false,
  };
}

@immutable
class EditorText {
  const EditorText(this.text, this.ranges);

  final String text;
  final List<FormatRange> ranges;
}

/// Bridge between the composer text (marks as ranges, blocks as visible line
/// prefixes) and the [RichDocument].
abstract class RichEditorText {
  static final _heading = RegExp(r'^(#{1,6}) ');
  static final _ordered = RegExp(r'^\d{1,9}\. ');
  static final _checklist = RegExp(r'^([☐☑]) ');
  static final _oneLineMaths = RegExp(r'^\$\$(.+)\$\$$');
  static final _language = RegExp(r'^[a-z0-9+#.\-]{1,20}$');

  static const _inlineKinds = {
    RangeKind.bold: InlineMark.bold,
    RangeKind.italic: InlineMark.italic,
    RangeKind.underline: InlineMark.underline,
    RangeKind.strike: InlineMark.strike,
    RangeKind.code: InlineMark.code,
    RangeKind.spoiler: InlineMark.spoiler,
  };

  static ({LineKind kind, int prefix, int level}) _blockOf(String line) {
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      return (
        kind: LineKind.heading,
        prefix: heading[0]!.length,
        level: heading[1]!.length,
      );
    }
    if (line.startsWith('> ')) {
      return (kind: LineKind.quote, prefix: 2, level: 1);
    }
    if (line.startsWith('- ')) {
      return (kind: LineKind.bullet, prefix: 2, level: 1);
    }
    final ordered = _ordered.firstMatch(line);
    if (ordered != null) {
      return (kind: LineKind.ordered, prefix: ordered[0]!.length, level: 1);
    }
    if (_checklist.hasMatch(line)) {
      return (kind: LineKind.checklist, prefix: 2, level: 1);
    }
    return (kind: LineKind.paragraph, prefix: 0, level: 1);
  }

  /// Classifies every line of [text] with the same rules as [build].
  static List<LineInfo> analyze(String text) {
    final result = <LineInfo>[];
    var offset = 0;
    LineKind? fence;
    for (final line in text.split('\n')) {
      final start = offset;
      final end = start + line.length;
      offset = end + 1;
      LineInfo info(LineKind kind, {int prefix = 0, int level = 1}) => LineInfo(
        start: start,
        end: end,
        kind: kind,
        prefixLength: prefix,
        level: level,
      );
      if (fence == LineKind.codeBody) {
        if (line == '```') fence = null;
        result.add(info(line == '```' ? LineKind.fence : LineKind.codeBody));
        continue;
      }
      if (fence == LineKind.mathsBody) {
        if (line == r'$$') fence = null;
        result.add(info(line == r'$$' ? LineKind.fence : LineKind.mathsBody));
        continue;
      }
      if (line.startsWith('```')) {
        fence = LineKind.codeBody;
        result.add(info(LineKind.fence));
        continue;
      }
      if (line == r'$$') {
        fence = LineKind.mathsBody;
        result.add(info(LineKind.fence));
        continue;
      }
      if (_oneLineMaths.hasMatch(line)) {
        result.add(info(LineKind.mathsBody));
        continue;
      }
      final block = _blockOf(line);
      result.add(info(block.kind, prefix: block.prefix, level: block.level));
    }
    return result;
  }

  static RichDocument build(String text, List<FormatRange> ranges) {
    final blocks = <Block>[];
    final lines = text.split('\n');
    var offset = 0;
    BlockKind? fence;
    String? fenceLanguage;
    var fenceFrom = 0;
    var fenceTo = 0;
    final fenceLines = <String>[];
    bool hidden(int from, int to) => ranges.any(
      (r) => r.kind == RangeKind.spoiler && r.start < to && r.end > from,
    );
    Block hiddenLine(String line) => Block(BlockKind.paragraph, [
      TextRun(line, marks: const {InlineMark.code, InlineMark.spoiler}),
    ]);
    void closeFence() {
      final kind = fence;
      if (kind == null) return;
      blocks.addAll(
        hidden(fenceFrom, fenceTo)
            ? fenceLines.map(hiddenLine)
            : [
                Block(
                  kind,
                  [TextRun(fenceLines.join('\n'))],
                  language: kind == BlockKind.codeBlock ? fenceLanguage : null,
                ),
              ],
      );
      fence = null;
      fenceLanguage = null;
      fenceLines.clear();
    }

    for (final line in lines) {
      final lineStart = offset;
      offset += line.length + 1;
      if (fence != null) {
        fenceTo = lineStart + line.length;
        final closing = line == (fence == BlockKind.codeBlock ? '```' : r'$$');
        if (closing) closeFence();
        if (!closing) fenceLines.add(line);
        continue;
      }
      if (line.startsWith('```')) {
        fenceFrom = lineStart;
        fenceTo = lineStart + line.length;
        fence = BlockKind.codeBlock;
        final language = line.substring(3).trim().toLowerCase();
        fenceLanguage = _language.hasMatch(language) ? language : null;
        continue;
      }
      if (line == r'$$') {
        fenceFrom = lineStart;
        fenceTo = lineStart + line.length;
        fence = BlockKind.mathsBlock;
        continue;
      }
      final oneLine = _oneLineMaths.firstMatch(line);
      if (oneLine != null) {
        blocks.add(
          hidden(lineStart, lineStart + line.length)
              ? hiddenLine(line)
              : Block(BlockKind.mathsBlock, [TextRun(oneLine[1]!)]),
        );
        continue;
      }
      final found = _blockOf(line);
      final kind = switch (found.kind) {
        LineKind.heading => BlockKind.heading,
        LineKind.quote => BlockKind.quote,
        LineKind.bullet => BlockKind.bullet,
        LineKind.ordered => BlockKind.ordered,
        LineKind.checklist => BlockKind.checklist,
        _ => BlockKind.paragraph,
      };
      final prefix = found.prefix;
      final level = found.level;
      final checked = found.kind == LineKind.checklist && line.startsWith('☑');
      blocks.add(
        Block(
          kind,
          _inlines(line.substring(prefix), lineStart + prefix, ranges),
          level: level,
          checked: checked,
        ),
      );
    }
    closeFence();
    return RichDocument(blocks);
  }

  static List<Inline> _inlines(
    String content,
    int contentStart,
    List<FormatRange> ranges,
  ) {
    final end = contentStart + content.length;
    final local = [
      for (final range in ranges)
        if (range.end > contentStart && range.start < end)
          FormatRange(
            range.start < contentStart ? contentStart : range.start,
            range.end > end ? end : range.end,
            range.kind,
            link: range.link,
          ),
    ];
    final maths = local.where((r) => r.kind == RangeKind.maths).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <Inline>[];
    var cursor = contentStart;
    void plain(int from, int to) {
      if (to <= from) return;
      final points = {
        from,
        to,
        for (final r in local)
          if (r.kind != RangeKind.maths) ...[
            if (r.start > from && r.start < to) r.start,
            if (r.end > from && r.end < to) r.end,
          ],
      }.toList()..sort();
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i];
        final b = points[i + 1];
        final covering = local.where(
          (r) => r.kind != RangeKind.maths && r.start <= a && r.end >= b,
        );
        result.add(
          TextRun(
            content.substring(a - contentStart, b - contentStart),
            marks: {for (final r in covering) ?_inlineKinds[r.kind]},
            link: covering
                .where((r) => r.kind == RangeKind.link)
                .firstOrNull
                ?.link,
          ),
        );
      }
    }

    for (final range in maths) {
      final start = range.start < cursor ? cursor : range.start;
      if (start >= range.end) continue;
      plain(cursor, start);
      final tex = content.substring(
        start - contentStart,
        range.end - contentStart,
      );
      final spoiler = local.any(
        (r) =>
            r.kind == RangeKind.spoiler && r.start < range.end && r.end > start,
      );
      result.add(
        spoiler
            ? TextRun(tex, marks: const {InlineMark.code, InlineMark.spoiler})
            : MathsInline(tex),
      );
      cursor = range.end;
    }
    plain(cursor, end);
    return result;
  }

  static EditorText render(RichDocument input) {
    final doc = input.normalized();
    final text = StringBuffer();
    final ranges = <FormatRange>[];
    var orderedIndex = 0;
    var previousKind = BlockKind.paragraph;
    var first = true;
    for (final block in doc.blocks) {
      if (!first) text.write('\n');
      first = false;
      orderedIndex = block.kind == BlockKind.ordered
          ? (previousKind == BlockKind.ordered ? orderedIndex + 1 : 1)
          : 0;
      previousKind = block.kind;
      switch (block.kind) {
        case BlockKind.codeBlock:
          text.write('```${block.language ?? ''}\n${block.text}\n```');
          continue;
        case BlockKind.mathsBlock:
          text.write('\$\$\n${block.text}\n\$\$');
          continue;
        case BlockKind.paragraph:
          break;
        case BlockKind.heading:
          text.write('${'#' * block.level} ');
        case BlockKind.quote:
          text.write('> ');
        case BlockKind.bullet:
          text.write('- ');
        case BlockKind.ordered:
          text.write('$orderedIndex. ');
        case BlockKind.checklist:
          text.write(block.checked ? '☑ ' : '☐ ');
      }
      for (final inline in block.inlines) {
        final start = text.length;
        switch (inline) {
          case TextRun():
            text.write(inline.text);
            for (final mark in inline.marks) {
              ranges.add(
                FormatRange(
                  start,
                  text.length,
                  _inlineKinds.entries.firstWhere((e) => e.value == mark).key,
                ),
              );
            }
            if (inline.link != null) {
              ranges.add(
                FormatRange(
                  start,
                  text.length,
                  RangeKind.link,
                  link: inline.link,
                ),
              );
            }
          case MathsInline():
            text.write(inline.tex);
            ranges.add(FormatRange(start, text.length, RangeKind.maths));
        }
      }
    }
    return EditorText(text.toString(), ranges);
  }

  /// True when opening [doc] in the editor and reading it back gives the same
  /// document (a paragraph that starts like a prefix does not).
  static bool roundTrips(RichDocument doc) {
    final editor = render(doc);
    return build(editor.text, editor.ranges).normalized() == doc.normalized();
  }
}
