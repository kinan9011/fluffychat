// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/search/search_query.dart';

void main() {
  group('SearchQuery.parse', () {
    test('lowercases, trims and splits on whitespace', () {
      final query = SearchQuery.parse('  Hello   WORLD\tnow ');
      expect(query.terms, ['hello', 'world', 'now']);
      expect(query.text, 'hello world now');
    });

    test('blank input has no terms', () {
      expect(SearchQuery.parse('   \n ').isEmpty, isTrue);
      expect(SearchQuery.parse('').terms, isEmpty);
    });

    test('control and bidi characters are removed', () {
      final query = SearchQuery.parse('a\u202Eb\u0000c d\u200Be');
      expect(query.terms.join(' '), isNot(contains('\u202E')));
      expect(query.terms.join(' '), isNot(contains('\u0000')));
      expect(query.terms.join(' '), isNot(contains('\u200B')));
    });

    test('at most 8 terms are kept', () {
      final query = SearchQuery.parse('a b c d e f g h i j');
      expect(query.terms, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
    });

    test('a term is cut at 64 characters', () {
      final query = SearchQuery.parse('x' * 200);
      expect(query.terms.single.length, SearchQuery.maxTermChars);
    });

    test('the raw input is cut at 128 characters before it is split', () {
      final query = SearchQuery.parse('${'ab ' * 100}needle');
      expect(query.terms.length, SearchQuery.maxTerms);
      expect(query.terms, isNot(contains('needle')));
    });

    test('the cut never splits an emoji', () {
      final query = SearchQuery.parse('${'a' * 64} ${'b' * 62}😀');
      expect(query.terms.last, '${'b' * 62}😀');
    });
  });
}
