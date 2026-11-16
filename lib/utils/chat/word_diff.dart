// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/config/design_constants.dart';

enum DiffKind { same, added, removed }

class DiffSegment {
  const DiffSegment(this.text, this.kind);

  final String text;
  final DiffKind kind;
}

final _token = RegExp(r'\s+|\S+');

bool _isSpace(String text) => text.trim().isEmpty;

/// Word level difference between two versions of a text. Both inputs are
/// untrusted: beyond [RichLimits.maxDiffTokens] tokens a side is shown as one
/// replaced block instead of running the quadratic comparison.
List<DiffSegment> wordDiff(String before, String after) {
  if (before == after) {
    return before.isEmpty ? const [] : [DiffSegment(before, DiffKind.same)];
  }
  final a = _token.allMatches(before).map((m) => m[0]!).toList();
  final b = _token.allMatches(after).map((m) => m[0]!).toList();
  if (a.length > RichLimits.maxDiffTokens ||
      b.length > RichLimits.maxDiffTokens) {
    return [
      if (before.isNotEmpty) DiffSegment(before, DiffKind.removed),
      if (after.isNotEmpty) DiffSegment(after, DiffKind.added),
    ];
  }
  final width = b.length + 1;
  final lcs = Uint16List((a.length + 1) * width);
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i * width + j] = a[i] == b[j]
          ? lcs[(i + 1) * width + j + 1] + 1
          : (lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]
                ? lcs[(i + 1) * width + j]
                : lcs[i * width + j + 1]);
    }
  }
  final raw = <DiffSegment>[];
  void add(String text, DiffKind kind) {
    if (raw.isNotEmpty && raw.last.kind == kind) {
      raw.last = DiffSegment(raw.last.text + text, kind);
      return;
    }
    raw.add(DiffSegment(text, kind));
  }

  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      add(a[i], DiffKind.same);
      i++;
      j++;
      continue;
    }
    final remove =
        j >= b.length ||
        (i < a.length && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]);
    if (remove) {
      add(a[i], DiffKind.removed);
      i++;
      continue;
    }
    add(b[j], DiffKind.added);
    j++;
  }
  return _absorbSpaces(raw);
}

/// A lone space between two changed words belongs to both sides, so
/// "an hour" becoming "20 minutes" reads as one removal and one addition.
List<DiffSegment> _absorbSpaces(List<DiffSegment> raw) {
  final result = <DiffSegment>[];
  var removed = '';
  var added = '';
  void flush() {
    if (removed.isNotEmpty) result.add(DiffSegment(removed, DiffKind.removed));
    if (added.isNotEmpty) result.add(DiffSegment(added, DiffKind.added));
    removed = '';
    added = '';
  }

  for (var k = 0; k < raw.length; k++) {
    final segment = raw[k];
    switch (segment.kind) {
      case DiffKind.removed:
        removed += segment.text;
      case DiffKind.added:
        added += segment.text;
      case DiffKind.same:
        final between =
            removed.isNotEmpty &&
            added.isNotEmpty &&
            _isSpace(segment.text) &&
            k + 1 < raw.length &&
            raw[k + 1].kind != DiffKind.same;
        if (between) {
          removed += segment.text;
          added += segment.text;
          continue;
        }
        flush();
        result.add(segment);
    }
  }
  flush();
  return result;
}
