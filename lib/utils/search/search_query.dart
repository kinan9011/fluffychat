// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:odango/utils/chat/display_text.dart';

/// What the user typed, reduced to a few lowercase terms. The raw text is not
/// kept anywhere else and is never logged.
class SearchQuery {
  const SearchQuery._(this.terms);

  static const maxRawChars = 128;
  static const maxTerms = 8;
  static const maxTermChars = 64;

  static const empty = SearchQuery._([]);

  final List<String> terms;

  bool get isEmpty => terms.isEmpty;

  String get text => terms.join(' ');

  static String normalize(String raw) => safeDisplayText(
    raw.characters.take(maxRawChars).toString(),
    maxGraphemes: maxRawChars,
  ).toLowerCase();

  factory SearchQuery.parse(String raw) {
    final terms = normalize(raw)
        .split(' ')
        .where((term) => term.isNotEmpty)
        .map((term) => term.characters.take(maxTermChars).toString())
        .take(maxTerms)
        .toList();
    return terms.isEmpty ? empty : SearchQuery._(terms);
  }
}
