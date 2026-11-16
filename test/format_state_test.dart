// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/format_state.dart';
import 'package:flutter/widgets.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';

FormatState state(List<FormatRange> ranges) => FormatState(ranges: ranges);

const bold = RangeKind.bold;

void main() {
  group('applyTextChange', () {
    test('typing inside a range extends it', () {
      final s = state([const FormatRange(0, 4, bold)]);
      s.applyTextChange('abcd', 'abXcd');
      expect(s.ranges, [const FormatRange(0, 5, bold)]);
    });

    test('typing at the end does not extend it without a pending mark', () {
      final s = state([const FormatRange(0, 4, bold)]);
      s.applyTextChange('abcd', 'abcdX');
      expect(s.ranges, [const FormatRange(0, 4, bold)]);
    });

    test('typing at the end with a pending mark formats the new text', () {
      final s = state([const FormatRange(0, 4, bold)])..pending = {bold};
      s.applyTextChange('abcd', 'abcdX');
      expect(s.ranges, [const FormatRange(0, 5, bold)]);
    });

    test('a pending mark formats text typed in plain territory', () {
      final s = FormatState()..pending = {RangeKind.italic};
      s.applyTextChange('ab', 'abXY');
      expect(s.ranges, [const FormatRange(2, 4, RangeKind.italic)]);
    });

    test('inserting before a range shifts it', () {
      final s = state([const FormatRange(2, 4, bold)]);
      s.applyTextChange('abcd', 'XYabcd');
      expect(s.ranges, [const FormatRange(4, 6, bold)]);
    });

    test('deleting the whole range drops it', () {
      final s = state([const FormatRange(1, 3, bold)]);
      s.applyTextChange('abcd', 'ad');
      expect(s.ranges, isEmpty);
    });

    test('a replacement across the end clips the range', () {
      final s = state([const FormatRange(0, 3, bold)]);
      s.applyTextChange('abcdef', 'abXf');
      expect(s.ranges, [const FormatRange(0, 2, bold)]);
    });

    test('a replacement across the start moves the range behind it', () {
      final s = state([const FormatRange(2, 5, bold)]);
      s.applyTextChange('abcdef', 'aXef');
      expect(s.ranges, [const FormatRange(2, 3, bold)]);
    });

    test('replacing text inside a range keeps the range around it', () {
      final s = state([const FormatRange(0, 4, bold)]);
      s.applyTextChange('abcd', 'aXd');
      expect(s.ranges, [const FormatRange(0, 3, bold)]);
    });

    test('a range behind the change shifts by the delta', () {
      final s = state([const FormatRange(4, 6, bold)]);
      s.applyTextChange('abcdef', 'adef');
      expect(s.ranges, [const FormatRange(2, 4, bold)]);
    });

    test('the caret places an insertion next to an equal neighbour', () {
      final withCaret = state([const FormatRange(1, 2, bold)]);
      withCaret.applyTextChange('ab', 'abb', caret: 2);
      expect(withCaret.ranges, [const FormatRange(2, 3, bold)]);
      final greedy = state([const FormatRange(1, 2, bold)]);
      greedy.applyTextChange('ab', 'abb');
      expect(greedy.ranges, [const FormatRange(1, 2, bold)]);
    });

    test('the caret places a deletion next to an equal neighbour', () {
      final s = state([const FormatRange(2, 3, bold)]);
      s.applyTextChange('abb', 'ab', caret: 1);
      expect(s.ranges, [const FormatRange(1, 2, bold)]);
    });

    test('a caret that does not match the change is ignored', () {
      final s = state([const FormatRange(0, 2, bold)]);
      s.applyTextChange('abcd', 'abXcd', caret: 0);
      expect(s.ranges, [const FormatRange(0, 2, bold)]);
    });

    test('a wholesale replacement drops everything', () {
      final s = state([const FormatRange(0, 3, bold)]);
      s.applyTextChange('abc', 'xyz');
      expect(s.ranges, isEmpty);
    });

    test('property: ranges stay valid over 300 random edits', () {
      final random = Random(3);
      var text = 'hello world';
      final s = state([
        const FormatRange(0, 5, bold),
        const FormatRange(6, 11, RangeKind.italic),
      ]);
      for (var i = 0; i < 300; i++) {
        final start = random.nextInt(text.length + 1);
        final end = start + random.nextInt(text.length - start + 1);
        final insert = 'abcXYZ'.substring(0, random.nextInt(4));
        final next = text.replaceRange(start, end, insert);
        s.applyTextChange(text, next);
        text = next;
        for (final range in s.ranges) {
          expect(range.start, greaterThanOrEqualTo(0));
          expect(range.start, lessThan(range.end));
          expect(range.end, lessThanOrEqualTo(text.length));
        }
        if (text.isEmpty) text = 'x';
      }
    });
  });

  group('toggle', () {
    test('adds, then removes over the same selection', () {
      final s = FormatState();
      s.toggle(bold, const TextRange(start: 1, end: 4));
      expect(s.ranges, [const FormatRange(1, 4, bold)]);
      expect(s.isActive(bold, const TextRange(start: 1, end: 4)), isTrue);
      s.toggle(bold, const TextRange(start: 1, end: 4));
      expect(s.ranges, isEmpty);
    });

    test('removing from the middle splits the range', () {
      final s = state([const FormatRange(0, 6, bold)]);
      s.toggle(bold, const TextRange(start: 2, end: 4));
      expect(s.ranges, [
        const FormatRange(0, 2, bold),
        const FormatRange(4, 6, bold),
      ]);
    });

    test('a partly covered selection adds and merges', () {
      final s = state([const FormatRange(0, 3, bold)]);
      expect(s.isActive(bold, const TextRange(start: 0, end: 5)), isFalse);
      s.toggle(bold, const TextRange(start: 0, end: 5));
      expect(s.ranges, [const FormatRange(0, 5, bold)]);
    });

    test('a collapsed selection toggles the pending mark', () {
      final s = FormatState();
      s.toggle(bold, const TextRange.collapsed(2));
      expect(s.pending, {bold});
      expect(s.isActive(bold, const TextRange.collapsed(2)), isTrue);
      s.toggle(bold, const TextRange.collapsed(2));
      expect(s.pending, isEmpty);
    });

    test('maths cuts other kinds out of its span', () {
      final s = state([const FormatRange(0, 6, bold)]);
      s.toggle(RangeKind.maths, const TextRange(start: 2, end: 4));
      expect(
        s.ranges,
        containsAll([
          const FormatRange(0, 2, bold),
          const FormatRange(4, 6, bold),
          const FormatRange(2, 4, RangeKind.maths),
        ]),
      );
      expect(
        s.ranges.where((r) => r.kind == bold && r.start < 4 && r.end > 2),
        isEmpty,
      );
    });

    test('the 501st range is refused', () {
      final s = state([
        for (var i = 0; i < RichLimits.maxRanges; i++)
          FormatRange(i * 2, i * 2 + 1, bold),
      ]);
      expect(
        s.toggle(RangeKind.italic, const TextRange(start: 0, end: 1)),
        isFalse,
      );
      expect(s.ranges.length, RichLimits.maxRanges);
    });
  });

  group('pending marks at the range cap', () {
    test('new text stays unformatted rather than passing 500 ranges', () {
      final s = state([
        for (var i = 0; i < RichLimits.maxRanges; i++)
          FormatRange(i * 2, i * 2 + 1, bold),
      ]);
      final text = 'ab' * RichLimits.maxRanges;
      s.pending = {RangeKind.italic};
      s.applyTextChange(text, '${text}c', caret: text.length + 1);
      expect(s.ranges.length, RichLimits.maxRanges);
      expect(s.ranges.any((r) => r.kind == RangeKind.italic), isFalse);
    });

    test('below the cap the pending mark still applies', () {
      final s = state(const []);
      s.pending = {RangeKind.italic};
      s.applyTextChange('', 'c', caret: 1);
      expect(s.ranges, [const FormatRange(0, 1, RangeKind.italic)]);
    });
  });

  group('links', () {
    test('a valid link is stored, replacing an older one', () {
      final s = FormatState();
      expect(
        s.setLink(
          const TextRange(start: 0, end: 3),
          Uri.parse('https://a.org'),
        ),
        isTrue,
      );
      expect(
        s.setLink(
          const TextRange(start: 0, end: 3),
          Uri.parse('https://b.org'),
        ),
        isTrue,
      );
      expect(s.ranges, [
        FormatRange(0, 3, RangeKind.link, link: Uri.parse('https://b.org')),
      ]);
    });

    test('a javascript link is refused and nothing changes', () {
      final s = FormatState();
      expect(
        s.setLink(
          const TextRange(start: 0, end: 3),
          Uri.parse('javascript:alert(1)'),
        ),
        isFalse,
      );
      expect(s.ranges, isEmpty);
    });

    test('clearLink removes it', () {
      final s = state([
        FormatRange(0, 3, RangeKind.link, link: Uri.parse('https://a.org')),
      ]);
      s.clearLink(const TextRange(start: 0, end: 3));
      expect(s.ranges, isEmpty);
    });
  });

  group('json', () {
    test('round trip', () {
      final s = FormatState(
        richIntent: true,
        ranges: [
          const FormatRange(0, 3, bold),
          FormatRange(2, 5, RangeKind.link, link: Uri.parse('https://a.org')),
        ],
      );
      final back = FormatState.fromJson(s.toJson(), 10);
      expect(back.richIntent, isTrue);
      expect(back.ranges, s.ranges);
    });

    test('hostile json yields a clean state', () {
      for (final bad in <Object?>[
        null,
        'x',
        5,
        <Object?>[],
        {'m': 'x'},
        {
          'm': <Object?>[5, 'a', null],
        },
        {
          'm': [
            [-1, 3, 0],
            [3, 3, 0],
            [4, 2, 0],
            [0, 99, 0],
            ['0', '3', 0],
            [0, 3, 99],
            [0, 3, -1],
            [0, 3, 6, 'javascript:alert(1)'],
            [0, 3, 6],
            [0, 3, 6, 5],
          ],
        },
      ]) {
        final s = FormatState.fromJson(bad, 10);
        expect(s.ranges, isEmpty, reason: '$bad');
      }
    });

    test('ten thousand entries are capped', () {
      final s = FormatState.fromJson({
        'm': [
          for (var i = 0; i < 10000; i++) [0, 1, 0],
        ],
      }, 10);
      expect(s.ranges.length, lessThanOrEqualTo(RichLimits.maxRanges));
    });

    test('unknown keys are ignored', () {
      final s = FormatState.fromJson({
        'x': 1,
        'r': true,
        'm': [
          [0, 2, 1],
        ],
      }, 5);
      expect(s.richIntent, isTrue);
      expect(s.ranges, [const FormatRange(0, 2, RangeKind.italic)]);
    });

    test('a valid link entry survives', () {
      final s = FormatState.fromJson({
        'm': [
          [0, 3, 6, 'https://a.org'],
        ],
      }, 5);
      expect(s.ranges.single.link, Uri.parse('https://a.org'));
    });
  });
}
