// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/search/local_search.dart';

/// The part of a message that is shown under its name in the results, with
/// the highlight ranges moved to match.
class Snippet {
  const Snippet(this.text, this.highlights);

  static const ellipsis = '…';

  final String text;
  final List<TextRange> highlights;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  factory Snippet.of(
    String text,
    List<TextRange> highlights, {
    int maxChars = 160,
    int lead = 40,
  }) {
    var start = highlights.isEmpty
        ? 0
        : (highlights.first.start - lead).clamp(0, text.length);
    if (start > 0 &&
        start < text.length &&
        _isLowSurrogate(text.codeUnitAt(start))) {
      start--;
    }
    var end = (start + maxChars).clamp(0, text.length);
    if (end < text.length && _isLowSurrogate(text.codeUnitAt(end))) end--;
    final prefix = start > 0 ? ellipsis : '';
    final suffix = end < text.length ? ellipsis : '';
    final shifted = <TextRange>[];
    for (final range in highlights) {
      if (range.end <= start || range.start >= end) continue;
      shifted.add((
        start:
            (range.start < start ? start : range.start) - start + prefix.length,
        end: (range.end > end ? end : range.end) - start + prefix.length,
      ));
    }
    return Snippet('$prefix${text.substring(start, end)}$suffix', shifted);
  }
}
