// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/status/status_policy.dart';

void main() {
  group('statusClearAt', () {
    test('one hour is exactly 60 minutes later', () {
      final now = DateTime(2030, 5, 10, 23, 30);
      expect(
        statusClearAt(StatusClearAfter.hour, now),
        DateTime(2030, 5, 11, 0, 30),
      );
    });

    test('today means the next local midnight', () {
      expect(
        statusClearAt(StatusClearAfter.today, DateTime(2030, 5, 10, 23, 59)),
        DateTime(2030, 5, 11),
      );
      expect(
        statusClearAt(StatusClearAfter.today, DateTime(2030, 5, 10, 0, 0)),
        DateTime(2030, 5, 11),
      );
    });

    test('today rolls over a month and a year', () {
      expect(
        statusClearAt(StatusClearAfter.today, DateTime(2030, 12, 31, 12)),
        DateTime(2031),
      );
      expect(
        statusClearAt(StatusClearAfter.today, DateTime(2030, 2, 28, 12)),
        DateTime(2030, 3),
      );
    });

    test('this week means the start of the next Monday', () {
      // 2030-05-10 is a Friday
      expect(
        statusClearAt(StatusClearAfter.week, DateTime(2030, 5, 10, 9)),
        DateTime(2030, 5, 13),
      );
      // a Sunday: the next day
      expect(
        statusClearAt(StatusClearAfter.week, DateTime(2030, 5, 12, 22)),
        DateTime(2030, 5, 13),
      );
      // a Monday: a full week, never "now"
      expect(
        statusClearAt(StatusClearAfter.week, DateTime(2030, 5, 13, 8)),
        DateTime(2030, 5, 20),
      );
    });

    test('this week rolls over the year end', () {
      // 2030-12-30 is a Monday
      expect(
        statusClearAt(StatusClearAfter.week, DateTime(2030, 12, 30, 8)),
        DateTime(2031, 1, 6),
      );
    });

    test('never has no deadline', () {
      expect(statusClearAt(StatusClearAfter.never, DateTime(2030)), isNull);
    });

    test('the result is always in the future', () {
      for (final after in StatusClearAfter.values) {
        for (var day = 1; day <= 28; day++) {
          final now = DateTime(2030, 3, day, 23, 59, 59);
          final at = statusClearAt(after, now);
          if (at != null) expect(at.isAfter(now), isTrue);
        }
      }
    });
  });

  group('sanitizeStatus', () {
    test('trims and keeps a normal text', () {
      expect(
        sanitizeStatus('  On holiday until Monday  '),
        'On holiday until Monday',
      );
    });

    test('control, line break and bidi override characters are dropped', () {
      final text = sanitizeStatus('a\u0000b\nc\u202Ed\u2066e')!;
      expect(text, 'a b c d e');
    });

    test('is cut to 255 characters', () {
      expect(sanitizeStatus('x' * 300)!.characters.length, maxStatusLength);
    });

    test('nothing left means clear', () {
      expect(sanitizeStatus('   \n\t '), isNull);
      expect(sanitizeStatus(''), isNull);
    });
  });

  group('displayStatus', () {
    test('null stays null and hostile text is cleaned', () {
      expect(displayStatus(null), isNull);
      expect(displayStatus('hi\u202Ethere'), 'hi there');
      expect(displayStatus('  \n '), isNull);
      expect(displayStatus('x' * 400)!.characters.length, maxStatusLength);
    });
  });
}
