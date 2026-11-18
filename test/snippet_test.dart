// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/search/snippet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a short text is shown as it is', () {
    final snippet = Snippet.of('hello world', [(start: 6, end: 11)]);
    expect(snippet.text, 'hello world');
    expect(snippet.highlights, [(start: 6, end: 11)]);
  });

  test('a long text is cut around the first hit with ellipses', () {
    final text = '${'a' * 200} needle ${'b' * 200}';
    final hit = text.indexOf('needle');
    final snippet = Snippet.of(text, [(start: hit, end: hit + 6)]);
    expect(snippet.text.startsWith(Snippet.ellipsis), isTrue);
    expect(snippet.text.endsWith(Snippet.ellipsis), isTrue);
    expect(snippet.text.length, lessThanOrEqualTo(160 + 2));
    final range = snippet.highlights.single;
    expect(snippet.text.substring(range.start, range.end), 'needle');
  });

  test('a hit near the start has no leading ellipsis', () {
    final text = 'needle ${'b' * 300}';
    final snippet = Snippet.of(text, [(start: 0, end: 6)]);
    expect(snippet.text.startsWith(Snippet.ellipsis), isFalse);
    expect(snippet.text.endsWith(Snippet.ellipsis), isTrue);
    expect(snippet.highlights.single, (start: 0, end: 6));
  });

  test('a text without hits starts at the beginning', () {
    final snippet = Snippet.of('x' * 300, const []);
    expect(snippet.text.startsWith('x'), isTrue);
    expect(snippet.highlights, isEmpty);
  });

  test(
    'a hit that falls outside the cut is dropped, one that straddles it is clipped',
    () {
      final text = '${'a' * 10} first ${'b' * 300} second';
      final first = text.indexOf('first');
      final second = text.indexOf('second');
      final snippet = Snippet.of(text, [
        (start: first, end: first + 5),
        (start: second, end: second + 6),
      ]);
      expect(snippet.highlights.length, 1);
    },
  );

  test('the cut never splits an emoji', () {
    final text = '${'😀' * 200} needle ${'😀' * 200}';
    final hit = text.indexOf('needle');
    final snippet = Snippet.of(text, [(start: hit, end: hit + 6)]);
    final runes = snippet.text.runes.toList();
    expect(runes.any((r) => r >= 0xD800 && r <= 0xDFFF), isFalse);
  });

  test('every range stays inside the text', () {
    final text = '${'a' * 400}needle';
    final hit = text.indexOf('needle');
    final snippet = Snippet.of(text, [(start: hit, end: hit + 6)]);
    for (final range in snippet.highlights) {
      expect(range.start, greaterThanOrEqualTo(0));
      expect(range.end, lessThanOrEqualTo(snippet.text.length));
      expect(range.start, lessThan(range.end));
    }
  });
}
