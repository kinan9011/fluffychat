// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:odango/utils/search/local_search.dart';
import 'package:odango/utils/search/search_filter.dart';
import 'package:odango/utils/search/search_kind.dart';

/// The chips above the results of the global search.
enum SearchSection { all, chats, messages, media, files, links, publicRooms }

/// Media, Files and Links are shortcuts for the type facet of the filter
/// sheet: the chip row and the sheet always describe the same state.
abstract final class SearchSections {
  static const _typeSets = <SearchSection, Set<SearchType>>{
    SearchSection.media: {SearchType.photos, SearchType.videos},
    SearchSection.files: {SearchType.files},
    SearchSection.links: {SearchType.links},
  };

  static bool ownsTypes(SearchSection section) =>
      _typeSets.containsKey(section);

  /// The filter after the user tapped the chip [section].
  static MessageSearchFilter select(
    SearchSection section,
    MessageSearchFilter filter,
    SearchSection current,
  ) {
    final types = _typeSets[section];
    if (types != null) return filter.copyWith(types: types);
    if (ownsTypes(current)) return filter.copyWith(types: const {});
    return filter;
  }

  /// The chip that is selected after the sheet returned [filter].
  static SearchSection after(
    MessageSearchFilter filter,
    SearchSection current,
  ) {
    for (final entry in _typeSets.entries) {
      if (setEquals(entry.value, filter.types)) return entry.key;
    }
    return ownsTypes(current) ? SearchSection.all : current;
  }

  static const maxMessages = 200;

  /// Index and server hits as one list: newest first, every message once.
  static List<SearchHit> mergeMessages(
    Iterable<SearchHit> local,
    Iterable<SearchHit> server, {
    int limit = maxMessages,
  }) {
    final byKey = <String, SearchHit>{};
    for (final hit in [...local, ...server]) {
      byKey.putIfAbsent(hit.message.key, () => hit);
    }
    final merged = byKey.values.toList()
      ..sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return merged.take(limit).toList();
  }
}
