// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/utils/search/search_query.dart';

typedef TextRange = ({int start, int end});

class SearchHit {
  const SearchHit(this.message, this.highlights);

  final IndexedMessage message;

  /// Where the query terms are in [IndexedMessage.text], sorted, not
  /// overlapping.
  final List<TextRange> highlights;
}

/// Runs a query over index entries. Everything that must not be shown is
/// dropped here, before the filter: rooms the user is no longer in and
/// messages the retention timer of their room hides.
abstract final class LocalSearch {
  static const defaultLimit = 100;

  static List<SearchHit> run(
    Iterable<IndexedMessage> entries,
    SearchQuery query,
    MessageSearchFilter filter, {
    required DateTime now,
    required RetentionPolicy? Function(String roomId) retentionOf,
    required bool Function(String roomId) roomVisible,
    int limit = defaultLimit,
  }) {
    if (query.isEmpty && filter.isEmpty) return const [];
    final patterns = _patterns(query);
    final hits = <IndexedMessage>[];
    for (final entry in entries) {
      if (!roomVisible(entry.roomId)) continue;
      final hidden = retentionOf(entry.roomId)?.hidesAt(
        DateTime.fromMillisecondsSinceEpoch(entry.timestamp),
        entry.kind.eventType,
        now,
      );
      if (hidden == true) continue;
      if (!filter.matches(entry, now)) continue;
      if (!patterns.every((pattern) => pattern.hasMatch(entry.text))) continue;
      hits.add(entry);
    }
    hits.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return [
      for (final entry in hits.take(limit))
        SearchHit(entry, highlights(entry.text, query)),
    ];
  }

  static List<RegExp> _patterns(SearchQuery query) => [
    for (final term in query.terms)
      RegExp(RegExp.escape(term), caseSensitive: false, unicode: true),
  ];

  /// The first occurrence of every term (any case), overlapping ranges
  /// merged.
  static List<TextRange> highlights(String text, SearchQuery query) {
    final found = <TextRange>[];
    for (final pattern in _patterns(query)) {
      final match = pattern.firstMatch(text);
      if (match != null) found.add((start: match.start, end: match.end));
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    final merged = <TextRange>[];
    for (final range in found) {
      if (merged.isNotEmpty && range.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add((
          start: last.start,
          end: range.end > last.end ? range.end : last.end,
        ));
        continue;
      }
      merged.add(range);
    }
    return merged;
  }
}
