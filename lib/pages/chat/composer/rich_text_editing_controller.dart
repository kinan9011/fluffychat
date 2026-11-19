// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/rich_text/editor_text.dart';
import 'package:odango/utils/rich_text/format_range.dart';
import 'package:odango/utils/rich_text/format_state.dart';
import 'package:odango/utils/rich_text/link_policy.dart';
import 'package:odango/utils/rich_text/rich_document.dart';
import 'package:odango/widgets/adaptive_dialogs/show_text_input_dialog.dart';

class _Snapshot {
  const _Snapshot(this.value, this.format);

  final TextEditingValue value;
  final FormatState format;
}

/// The composer text plus its inline formatting. Marks are ranges that follow
/// the text through edits; blocks are visible line prefixes (`# `, `> `, `- `,
/// `1. `, `☐ `) and fences. Wholesale replacements must use [resetTo].
class RichTextEditingController extends TextEditingController {
  RichTextEditingController({super.text});

  final format = FormatState();
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];
  var _restoring = false;
  var _typingRun = false;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  Map<String, Object?>? draftFormat() =>
      format.isEmpty ? null : format.toJson();

  bool isActive(RangeKind kind) => format.isActive(
    kind,
    TextRange(start: selection.start, end: selection.end),
  );

  LineInfo? get caretLine {
    final offset = selection.isValid ? selection.start : text.length;
    return RichEditorText.analyze(
      text,
    ).where((line) => line.start <= offset && offset <= line.end).firstOrNull;
  }

  @override
  set value(TextEditingValue newValue) {
    if (_restoring) {
      super.value = newValue;
      return;
    }
    final old = value;
    if (newValue.text == old.text) {
      if (newValue.selection != old.selection) format.pending = {};
      super.value = newValue;
      return;
    }
    final next = _continueList(old, newValue);
    _record(old, next);
    format.applyTextChange(
      old.text,
      next.text,
      caret: next.selection.isCollapsed ? next.selection.baseOffset : null,
    );
    super.value = next;
  }

  void _record(TextEditingValue old, TextEditingValue next) {
    final typed =
        next.text.length == old.text.length + 1 &&
        !_isSpace(_insertedChar(old.text, next.text));
    if (!(typed && _typingRun)) _push();
    _typingRun = typed;
    _redo.clear();
  }

  static String _insertedChar(String before, String after) {
    var prefix = 0;
    while (prefix < before.length && before[prefix] == after[prefix]) {
      prefix++;
    }
    return after[prefix];
  }

  static bool _isSpace(String char) => char.trim().isEmpty;

  void _push() {
    _undo.add(_Snapshot(value, format.copy()));
    if (_undo.length > RichLimits.maxUndo) _undo.removeAt(0);
  }

  void _restore(_Snapshot snapshot) {
    _restoring = true;
    super.value = snapshot.value;
    format.assign(snapshot.format);
    _restoring = false;
    _typingRun = false;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_Snapshot(value, format.copy()));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_Snapshot(value, format.copy()));
    _restore(_redo.removeLast());
  }

  void resetTo(String text, {FormatState? state}) {
    _restoring = true;
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    format.assign(state ?? FormatState());
    _restoring = false;
    _undo.clear();
    _redo.clear();
    _typingRun = false;
    notifyListeners();
  }

  void toggleInline(RangeKind kind) {
    if (!selection.isValid) return;
    final collapsed = selection.isCollapsed;
    if (!collapsed) _push();
    final changed = format.toggle(
      kind,
      TextRange(start: selection.start, end: selection.end),
    );
    if (!collapsed && !changed) _undo.removeLast();
    if (!collapsed && changed) _redo.clear();
    _typingRun = false;
    notifyListeners();
  }

  Future<void> toggleLink(BuildContext context) async {
    if (!selection.isValid) return;
    final range = TextRange(start: selection.start, end: selection.end);
    if (!range.isCollapsed && format.isActive(RangeKind.link, range)) {
      _push();
      format.clearLink(range);
      notifyListeners();
      return;
    }
    final l10n = L10n.of(context);
    final before = text;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.addLink,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      validator: (text) =>
          LinkPolicy.parse(text) == null ? l10n.invalidUrl : null,
      hintText: 'www...',
      keyboardType: TextInputType.url,
    );
    final uri = input == null ? null : LinkPolicy.parse(input);
    if (uri == null || text != before) return;
    if (range.isCollapsed) {
      final label = uri.toString();
      value = value.copyWith(
        text: text.replaceRange(range.start, range.start, label),
        selection: TextSelection.collapsed(offset: range.start + label.length),
      );
      format.setLink(
        TextRange(start: range.start, end: range.start + label.length),
        uri,
      );
      notifyListeners();
      return;
    }
    final saved = _Snapshot(value, format.copy());
    if (!format.setLink(range, uri)) return;
    _undo.add(saved);
    if (_undo.length > RichLimits.maxUndo) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  static String _prefixOf(LineKind kind, {int level = 1, int number = 1}) =>
      switch (kind) {
        LineKind.heading => '${'#' * level} ',
        LineKind.quote => '> ',
        LineKind.bullet => '- ',
        LineKind.ordered => '$number. ',
        LineKind.checklist => '☐ ',
        _ => '',
      };

  void toggleBlock(BlockKind kind, {int level = 1}) {
    final target = switch (kind) {
      BlockKind.heading => LineKind.heading,
      BlockKind.quote => LineKind.quote,
      BlockKind.bullet => LineKind.bullet,
      BlockKind.ordered => LineKind.ordered,
      BlockKind.checklist => LineKind.checklist,
      _ => null,
    };
    if (target == null) return;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid && !selection.isCollapsed
        ? selection.end - 1
        : start;
    final lines = RichEditorText.analyze(text)
        .where(
          (line) =>
              line.end >= start &&
              line.start <= end &&
              line.kind != LineKind.fence &&
              line.kind != LineKind.codeBody &&
              line.kind != LineKind.mathsBody,
        )
        .toList();
    if (lines.isEmpty) return;
    final headingLevel = lines.first.kind == LineKind.heading
        ? (lines.first.level < 3 ? lines.first.level + 1 : 0)
        : level;
    final prefixFor = switch ((
      target,
      lines.every((line) => line.kind == target),
    )) {
      (LineKind.heading, _) =>
        (int _) =>
            headingLevel == 0 ? '' : _prefixOf(target, level: headingLevel),
      (_, true) => (int _) => '',
      _ => (int index) => _prefixOf(target, number: index + 1),
    };
    int shift(int offset, int at, int removed, int added) => switch (offset) {
      _ when offset > at + removed => offset + added - removed,
      _ when offset > at => at + added,
      _ => offset,
    };
    final saved = _Snapshot(value, format.copy());
    var current = text;
    var selStart = selection.isValid ? selection.start : text.length;
    var selEnd = selection.isValid ? selection.end : text.length;
    var adding = false;
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      final prefix = prefixFor(i);
      adding = adding || prefix.isNotEmpty;
      final next = current.replaceRange(
        line.start,
        line.start + line.prefixLength,
        prefix,
      );
      format.applyTextChange(current, next);
      current = next;
      selStart = shift(selStart, line.start, line.prefixLength, prefix.length);
      selEnd = shift(selEnd, line.start, line.prefixLength, prefix.length);
    }
    if (current == text) return;
    _undo.add(saved);
    if (_undo.length > RichLimits.maxUndo) _undo.removeAt(0);
    _redo.clear();
    _typingRun = false;
    super.value = TextEditingValue(
      text: current,
      selection: TextSelection(baseOffset: selStart, extentOffset: selEnd),
    );
    if (adding) format.richIntent = true;
    notifyListeners();
  }

  void insertBlockFence(BlockKind kind) {
    final fence = switch (kind) {
      BlockKind.codeBlock => '```',
      BlockKind.mathsBlock => r'$$',
      _ => null,
    };
    if (fence == null) return;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final atLineStart = start == 0 || text[start - 1] == '\n';
    final lead = atLineStart ? '' : '\n';
    final selected = text.substring(start, end);
    final inserted = '$lead$fence\n$selected\n$fence';
    final caret = start + lead.length + fence.length + 1 + selected.length;
    value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection.collapsed(offset: caret),
    );
    format.richIntent = true;
    notifyListeners();
  }

  TextEditingValue _continueList(TextEditingValue old, TextEditingValue next) {
    if (!format.richIntent || !next.selection.isCollapsed) return next;
    final offset = next.selection.baseOffset;
    if (next.text.length != old.text.length + 1 ||
        offset < 1 ||
        next.text[offset - 1] != '\n' ||
        old.text != next.text.replaceRange(offset - 1, offset, '')) {
      return next;
    }
    final line = RichEditorText.analyze(
      old.text,
    ).where((l) => l.start <= offset - 1 && offset - 1 <= l.end).firstOrNull;
    if (line == null) return next;
    final continues = switch (line.kind) {
      LineKind.bullet ||
      LineKind.ordered ||
      LineKind.checklist ||
      LineKind.quote => true,
      _ => false,
    };
    if (!continues) return next;
    if (old.text.substring(line.start + line.prefixLength, line.end).isEmpty) {
      return TextEditingValue(
        text: old.text.replaceRange(
          line.start,
          line.start + line.prefixLength,
          '',
        ),
        selection: TextSelection.collapsed(offset: line.start),
      );
    }
    final number = line.kind == LineKind.ordered
        ? (int.tryParse(
                    old.text
                        .substring(line.start, line.start + line.prefixLength)
                        .replaceAll('. ', ''),
                  ) ??
                  0) +
              1
        : 1;
    final prefix = _prefixOf(line.kind, number: number);
    return TextEditingValue(
      text: next.text.replaceRange(offset, offset, prefix),
      selection: TextSelection.collapsed(offset: offset + prefix.length),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final tokens = AppTokens.of(context);
    final base = style ?? const TextStyle();
    final size = base.fontSize ?? 16;
    final source = text;
    final lines = RichEditorText.analyze(source);
    final points = <int>{0, source.length};
    for (final line in lines) {
      points
        ..add(line.start)
        ..add(min(line.end, source.length))
        ..add(min(line.start + line.prefixLength, source.length));
    }
    final ranges = format.ranges;
    for (final range in ranges) {
      points
        ..add(min(range.start, source.length))
        ..add(min(range.end, source.length));
    }
    final composing = value.composing;
    final underlineComposing =
        withComposing && composing.isValid && !composing.isCollapsed;
    if (underlineComposing) {
      points
        ..add(min(composing.start, source.length))
        ..add(min(composing.end, source.length));
    }
    final sorted = points.where((p) => p >= 0 && p <= source.length).toList()
      ..sort();
    final children = <TextSpan>[];
    var lineIndex = 0;
    for (var i = 0; i < sorted.length - 1; i++) {
      final from = sorted[i];
      final to = sorted[i + 1];
      if (to <= from) continue;
      while (lineIndex < lines.length - 1 && lines[lineIndex].end < from) {
        lineIndex++;
      }
      final line = lines.isEmpty ? null : lines[lineIndex];
      var segment = base;
      if (line != null) {
        final inPrefix = from < line.start + line.prefixLength;
        segment = switch (line.kind) {
          LineKind.heading => segment.copyWith(
            fontSize:
                size * const [1.6, 1.5, 1.4, 1.3, 1.2, 1.1][line.level - 1],
            fontWeight: FontWeight.w700,
            color: inPrefix ? tokens.mut : null,
          ),
          LineKind.quote => segment.copyWith(
            fontStyle: FontStyle.italic,
            color: inPrefix ? tokens.mut : null,
          ),
          LineKind.bullet || LineKind.ordered || LineKind.checklist =>
            inPrefix ? segment.copyWith(color: tokens.mut) : segment,
          LineKind.fence => AppTypography.mono.merge(
            segment.copyWith(color: tokens.mut),
          ),
          LineKind.codeBody || LineKind.mathsBody => AppTypography.mono.merge(
            segment.copyWith(backgroundColor: tokens.surf2),
          ),
          LineKind.paragraph => segment,
        };
      }
      final inVerbatim =
          line != null &&
          (line.kind == LineKind.codeBody ||
              line.kind == LineKind.mathsBody ||
              line.kind == LineKind.fence);
      if (!inVerbatim) {
        for (final range in ranges) {
          if (range.start > from || range.end < to) continue;
          segment = switch (range.kind) {
            RangeKind.bold => segment.copyWith(fontWeight: FontWeight.w700),
            RangeKind.italic => segment.copyWith(fontStyle: FontStyle.italic),
            RangeKind.underline => segment.copyWith(
              decoration: _decoration(segment, TextDecoration.underline),
            ),
            RangeKind.strike => segment.copyWith(
              decoration: _decoration(segment, TextDecoration.lineThrough),
            ),
            RangeKind.code => AppTypography.mono.merge(
              segment.copyWith(backgroundColor: tokens.surf2),
            ),
            RangeKind.spoiler => segment.copyWith(
              backgroundColor: tokens.mut.withValues(alpha: .3),
            ),
            RangeKind.link => segment.copyWith(
              color: tokens.acc,
              decoration: _decoration(segment, TextDecoration.underline),
            ),
            RangeKind.maths => AppTypography.mono.merge(
              segment.copyWith(backgroundColor: tokens.surf2),
            ),
          };
        }
      }
      if (underlineComposing &&
          from >= composing.start &&
          to <= composing.end) {
        segment = segment.copyWith(
          decoration: _decoration(segment, TextDecoration.underline),
        );
      }
      children.add(TextSpan(text: source.substring(from, to), style: segment));
    }
    return TextSpan(style: base, children: children);
  }

  static TextDecoration _decoration(TextStyle style, TextDecoration add) =>
      TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        add,
      ]);
}
