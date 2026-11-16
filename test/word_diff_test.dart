// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/chat/word_diff.dart';
import 'package:flutter_test/flutter_test.dart';

List<(DiffKind, String)> flat(List<DiffSegment> segments) => [
  for (final s in segments) (s.kind, s.text),
];

String keptAndRemoved(List<DiffSegment> s) =>
    s.where((e) => e.kind != DiffKind.added).map((e) => e.text).join();

String keptAndAdded(List<DiffSegment> s) =>
    s.where((e) => e.kind != DiffKind.removed).map((e) => e.text).join();

void main() {
  test('identical text is one same segment', () {
    expect(flat(wordDiff('a b c', 'a b c')), [(DiffKind.same, 'a b c')]);
  });

  test('two empty strings give nothing', () {
    expect(wordDiff('', ''), isEmpty);
  });

  test('from nothing is one added segment, to nothing one removed', () {
    expect(flat(wordDiff('', 'new text')), [(DiffKind.added, 'new text')]);
    expect(flat(wordDiff('old text', '')), [(DiffKind.removed, 'old text')]);
  });

  test('the mockup case: an hour becomes 20 minutes', () {
    expect(
      flat(
        wordDiff(
          'Testing it now, results in an hour.',
          'Testing it now, results in 20 minutes.',
        ),
      ),
      [
        (DiffKind.same, 'Testing it now, results in '),
        (DiffKind.removed, 'an hour.'),
        (DiffKind.added, '20 minutes.'),
      ],
    );
  });

  test('an insertion in the middle', () {
    expect(flat(wordDiff('a c', 'a b c')), [
      (DiffKind.same, 'a '),
      (DiffKind.added, 'b '),
      (DiffKind.same, 'c'),
    ]);
  });

  test('a deleted first word', () {
    expect(flat(wordDiff('one two', 'two')), [
      (DiffKind.removed, 'one '),
      (DiffKind.same, 'two'),
    ]);
  });

  test('whitespace only changes are shown', () {
    final result = wordDiff('a  b', 'a b');
    expect(keptAndRemoved(result), 'a  b');
    expect(keptAndAdded(result), 'a b');
    expect(result.any((s) => s.kind != DiffKind.same), isTrue);
  });

  test('the old and new text can always be rebuilt (200 seeded pairs)', () {
    final random = Random(9);
    const words = ['a', 'bb', 'ccc', 'عربي', '😀', 'é', ' ', '  ', '\n'];
    String text() => List.generate(
      random.nextInt(12),
      (_) => words[random.nextInt(words.length)],
    ).join();
    for (var i = 0; i < 200; i++) {
      final before = text();
      final after = text();
      final result = wordDiff(before, after);
      expect(keptAndRemoved(result), before, reason: '$before -> $after');
      expect(keptAndAdded(result), after, reason: '$before -> $after');
      for (var k = 1; k < result.length; k++) {
        expect(result[k].kind, isNot(result[k - 1].kind));
      }
    }
  });

  test(
    'two huge inputs fall back to one removed and one added segment fast',
    () {
      final before = List.generate(10000, (i) => 'w$i').join(' ');
      final after = List.generate(10000, (i) => 'x$i').join(' ');
      final watch = Stopwatch()..start();
      final result = wordDiff(before, after);
      expect(watch.elapsedMilliseconds, lessThan(200));
      expect(flat(result), [
        (DiffKind.removed, before),
        (DiffKind.added, after),
      ]);
    },
  );

  test('the token cap: 400 tokens are diffed, 401 are replaced as a whole', () {
    // 200 words with the separating spaces make 399 tokens
    final base = List.generate(200, (i) => 'w$i').join(' ');
    final edited = '${base}x';
    expect(wordDiff(base, edited).length, greaterThan(1));
    final long = List.generate(201, (i) => 'w$i').join(' ');
    final longEdited = '${long}x';
    expect(flat(wordDiff(long, longEdited)), [
      (DiffKind.removed, long),
      (DiffKind.added, longEdited),
    ]);
    expect(RichLimits.maxDiffTokens, 400);
  });
}
