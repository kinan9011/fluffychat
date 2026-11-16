// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

enum InlineMark { bold, italic, underline, strike, code, spoiler }

sealed class Inline {
  const Inline();
}

@immutable
final class TextRun extends Inline {
  const TextRun(this.text, {this.marks = const {}, this.link});

  final String text;
  final Set<InlineMark> marks;
  final Uri? link;

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.text == text &&
      other.link == link &&
      setEquals(other.marks, marks);

  @override
  int get hashCode => Object.hash(text, link, Object.hashAllUnordered(marks));
}

@immutable
final class MathsInline extends Inline {
  const MathsInline(this.tex);

  final String tex;

  @override
  bool operator ==(Object other) => other is MathsInline && other.tex == tex;

  @override
  int get hashCode => tex.hashCode;
}

enum BlockKind {
  paragraph,
  heading,
  quote,
  bullet,
  ordered,
  checklist,
  codeBlock,
  mathsBlock,
}

@immutable
class Block {
  const Block(
    this.kind,
    this.inlines, {
    this.level = 1,
    this.checked = false,
    this.language,
  });

  final BlockKind kind;
  final List<Inline> inlines;
  final int level;
  final bool checked;
  final String? language;

  bool get isVerbatim =>
      kind == BlockKind.codeBlock || kind == BlockKind.mathsBlock;

  String get text => inlines
      .map(
        (inline) => switch (inline) {
          TextRun() => inline.text,
          MathsInline() => inline.tex,
        },
      )
      .join();

  @override
  bool operator ==(Object other) =>
      other is Block &&
      other.kind == kind &&
      other.level == level &&
      other.checked == checked &&
      other.language == language &&
      listEquals(other.inlines, inlines);

  @override
  int get hashCode =>
      Object.hash(kind, level, checked, language, Object.hashAll(inlines));
}

@immutable
class RichDocument {
  const RichDocument(this.blocks);

  final List<Block> blocks;

  bool get isPlain => blocks.every(
    (block) =>
        block.kind == BlockKind.paragraph &&
        block.inlines.every(
          (inline) =>
              inline is TextRun && inline.marks.isEmpty && inline.link == null,
        ),
  );

  String get plainText => blocks.map((block) => block.text).join('\n');

  RichDocument normalized() {
    final kept = [for (final block in blocks) ?_normalizedBlock(block)];
    bool empty(Block b) => b.kind == BlockKind.paragraph && b.inlines.isEmpty;
    while (kept.isNotEmpty && empty(kept.first)) {
      kept.removeAt(0);
    }
    while (kept.isNotEmpty && empty(kept.last)) {
      kept.removeLast();
    }
    return RichDocument(kept);
  }

  static Block? _normalizedBlock(Block block) {
    final merged = <Inline>[];
    for (final inline in block.inlines) {
      if (inline is TextRun && inline.text.isEmpty) continue;
      if (inline is MathsInline && inline.tex.isEmpty) continue;
      final last = merged.isEmpty ? null : merged.last;
      if (inline is TextRun &&
          last is TextRun &&
          last.link == inline.link &&
          setEquals(last.marks, inline.marks)) {
        merged.last = TextRun(
          last.text + inline.text,
          marks: last.marks,
          link: last.link,
        );
        continue;
      }
      merged.add(inline);
    }
    if (block.isVerbatim && merged.length == 1 && merged.first is TextRun) {
      final run = merged.first as TextRun;
      var end = run.text.length;
      while (end > 0 && run.text.codeUnitAt(end - 1) == 0x0a) {
        end--;
      }
      final trimmed = run.text.substring(0, end);
      merged.clear();
      if (trimmed.isNotEmpty) merged.add(TextRun(trimmed));
    }
    if (merged.isEmpty && block.kind != BlockKind.paragraph) return null;
    return Block(
      block.kind,
      merged,
      level: block.kind == BlockKind.heading ? block.level.clamp(1, 6) : 1,
      checked: block.kind == BlockKind.checklist && block.checked,
      language: block.kind == BlockKind.codeBlock ? block.language : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RichDocument && listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hashAll(blocks);
}
