// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:flutter/widgets.dart' show TextRange;
import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/rich_text/format_range.dart';
import 'package:odango/utils/rich_text/link_policy.dart';

/// Inline formatting of the composer text as ranges over its UTF-16 offsets,
/// plus the flag that the user used the format controls ([richIntent]).
class FormatState {
  FormatState({List<FormatRange>? ranges, this.richIntent = false})
    : _ranges = [...?ranges];

  final List<FormatRange> _ranges;

  /// Set when a block format (list, heading...) was applied by the panel.
  bool richIntent;

  /// Marks for the characters typed next at a collapsed caret.
  Set<RangeKind> pending = {};

  List<FormatRange> get ranges => List.unmodifiable(_ranges);

  bool get isEmpty => _ranges.isEmpty && !richIntent;

  FormatState copy() =>
      FormatState(ranges: _ranges, richIntent: richIntent)
        ..pending = {...pending};

  void assign(FormatState other) {
    _ranges
      ..clear()
      ..addAll(other._ranges);
    richIntent = other.richIntent;
    pending = {...other.pending};
  }

  void clear() {
    _ranges.clear();
    richIntent = false;
    pending = {};
  }

  /// Where [before] became [after]: the start, the end of the replaced span
  /// in [before] and the inserted length. A collapsed caret says where a single
  /// insertion or deletion happened; without it, typing a character equal to
  /// its neighbour is ambiguous.
  static ({int prefix, int oldEnd, int inserted}) _locate(
    String before,
    String after,
    int? caret,
  ) {
    final delta = after.length - before.length;
    if (caret != null &&
        delta > 0 &&
        caret >= delta &&
        caret <= after.length &&
        before == after.replaceRange(caret - delta, caret, '')) {
      return (prefix: caret - delta, oldEnd: caret - delta, inserted: delta);
    }
    if (caret != null &&
        delta < 0 &&
        caret >= 0 &&
        caret - delta <= before.length &&
        before.replaceRange(caret, caret - delta, '') == after) {
      return (prefix: caret, oldEnd: caret - delta, inserted: 0);
    }
    final shortest = min(before.length, after.length);
    var prefix = 0;
    while (prefix < shortest &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    return (
      prefix: prefix,
      oldEnd: before.length - suffix,
      inserted: after.length - suffix - prefix,
    );
  }

  void applyTextChange(String before, String after, {int? caret}) {
    if (before == after) return;
    final delta = after.length - before.length;
    final (:prefix, :oldEnd, :inserted) = _locate(before, after, caret);
    final next = <FormatRange>[];
    for (final range in _ranges) {
      final start = range.start < prefix
          ? range.start
          : (range.start >= oldEnd ? range.start + delta : prefix + inserted);
      final end = range.end <= prefix
          ? range.end
          : (range.end >= oldEnd ? range.end + delta : prefix);
      if (start >= end) continue;
      next.add(
        FormatRange(
          start,
          min(end, after.length),
          range.kind,
          link: range.link,
        ),
      );
    }
    var result = _merged(next);
    if (inserted > 0 && pending.isNotEmpty) {
      final withPending = _merged([
        ...next,
        for (final kind in pending)
          FormatRange(prefix, prefix + inserted, kind),
      ]);
      if (withPending.length <= RichLimits.maxRanges) result = withPending;
    }
    _ranges
      ..clear()
      ..addAll(result);
  }

  static List<FormatRange> _merged(List<FormatRange> input) {
    final sorted = [...input]
      ..sort((a, b) {
        final byKind = a.kind.index.compareTo(b.kind.index);
        return byKind != 0 ? byKind : a.start.compareTo(b.start);
      });
    final result = <FormatRange>[];
    for (final range in sorted) {
      final last = result.isEmpty ? null : result.last;
      if (last != null &&
          last.kind == range.kind &&
          last.link == range.link &&
          range.start <= last.end) {
        result.last = FormatRange(
          last.start,
          max(last.end, range.end),
          last.kind,
          link: last.link,
        );
        continue;
      }
      result.add(range);
    }
    return result..sort((a, b) => a.start.compareTo(b.start));
  }

  bool _covered(RangeKind kind, int start, int end) {
    var cursor = start;
    final ofKind = _ranges.where((r) => r.kind == kind).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final range in ofKind) {
      if (range.end <= cursor) continue;
      if (range.start > cursor) return false;
      cursor = range.end;
      if (cursor >= end) return true;
    }
    return cursor >= end;
  }

  bool isActive(RangeKind kind, TextRange selection) {
    if (!selection.isValid) return false;
    if (selection.isCollapsed) return pending.contains(kind);
    return _covered(kind, selection.start, selection.end);
  }

  List<FormatRange> _without(RangeKind kind, int start, int end) {
    final result = <FormatRange>[];
    for (final range in _ranges) {
      if (range.kind != kind || range.end <= start || range.start >= end) {
        result.add(range);
        continue;
      }
      if (range.start < start) {
        result.add(FormatRange(range.start, start, kind, link: range.link));
      }
      if (range.end > end) {
        result.add(FormatRange(end, range.end, kind, link: range.link));
      }
    }
    return result;
  }

  /// Returns false when the range limit refuses the change.
  bool toggle(RangeKind kind, TextRange selection) {
    if (!selection.isValid || kind == RangeKind.link) return false;
    if (selection.isCollapsed) {
      pending = pending.contains(kind)
          ? ({...pending}..remove(kind))
          : {...pending, kind};
      return true;
    }
    final start = selection.start;
    final end = selection.end;
    if (_covered(kind, start, end)) {
      _replace(_without(kind, start, end));
      return true;
    }
    var next = [..._ranges];
    if (kind == RangeKind.maths) {
      for (final other in RangeKind.values) {
        if (other == RangeKind.maths) continue;
        next = _withoutIn(next, other, start, end);
      }
    }
    next.add(FormatRange(start, end, kind));
    final merged = _merged(next);
    if (merged.length > RichLimits.maxRanges) return false;
    _replace(merged);
    return true;
  }

  static List<FormatRange> _withoutIn(
    List<FormatRange> source,
    RangeKind kind,
    int start,
    int end,
  ) {
    final holder = FormatState(ranges: source);
    return holder._without(kind, start, end);
  }

  void _replace(List<FormatRange> next) {
    _ranges
      ..clear()
      ..addAll(_merged(next));
  }

  bool setLink(TextRange selection, Uri uri) {
    final checked = LinkPolicy.parse(uri.toString());
    if (checked == null || !selection.isValid || selection.isCollapsed) {
      return false;
    }
    final next = _without(RangeKind.link, selection.start, selection.end)
      ..add(
        FormatRange(
          selection.start,
          selection.end,
          RangeKind.link,
          link: checked,
        ),
      );
    final merged = _merged(next);
    if (merged.length > RichLimits.maxRanges) return false;
    _replace(merged);
    return true;
  }

  void clearLink(TextRange selection) {
    if (!selection.isValid) return;
    _replace(_without(RangeKind.link, selection.start, selection.end));
  }

  Map<String, Object?> toJson() => {
    'r': richIntent,
    'm': [
      for (final range in _ranges)
        [
          range.start,
          range.end,
          range.kind.index,
          if (range.link != null) range.link.toString(),
        ],
    ],
  };

  static FormatState fromJson(Object? json, int textLength) {
    final state = FormatState();
    if (json is! Map) return state;
    state.richIntent = json['r'] == true;
    final entries = json['m'];
    if (entries is! List) return state;
    final ranges = <FormatRange>[];
    for (final entry in entries) {
      if (ranges.length >= RichLimits.maxRanges) break;
      if (entry is! List || entry.length < 3) continue;
      final [start, end, kindIndex, ...] = entry;
      if (start is! int || end is! int || kindIndex is! int) continue;
      if (start < 0 || start >= end || end > textLength) continue;
      if (kindIndex < 0 || kindIndex >= RangeKind.values.length) continue;
      final kind = RangeKind.values[kindIndex];
      Uri? link;
      if (kind == RangeKind.link) {
        final raw = entry.length > 3 ? entry[3] : null;
        link = raw is String ? LinkPolicy.parse(raw) : null;
        if (link == null) continue;
      }
      ranges.add(FormatRange(start, end, kind, link: link));
    }
    return state.._replace(ranges);
  }
}
