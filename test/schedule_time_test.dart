// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/scheduling/schedule_time.dart';

void main() {
  final thursday = DateTime(2025, 11, 13, 14, 30);

  group('roundUpToStep', () {
    test('rounds up to the next five minutes', () {
      expect(
        ScheduleRules.roundUpToStep(DateTime(2025, 11, 13, 15, 31, 10)),
        DateTime(2025, 11, 13, 15, 35),
      );
    });

    test('keeps an exact boundary', () {
      expect(
        ScheduleRules.roundUpToStep(DateTime(2025, 11, 13, 15, 35)),
        DateTime(2025, 11, 13, 15, 35),
      );
    });

    test('rounds a boundary plus one second up', () {
      expect(
        ScheduleRules.roundUpToStep(DateTime(2025, 11, 13, 15, 35, 0, 1)),
        DateTime(2025, 11, 13, 15, 40),
      );
    });

    test('crosses midnight', () {
      expect(
        ScheduleRules.roundUpToStep(DateTime(2025, 11, 13, 23, 58)),
        DateTime(2025, 11, 14),
      );
    });
  });

  group('presets', () {
    test('values for Thursday 14:30', () {
      final presets = ScheduleRules.presets(thursday);
      expect(presets[SchedulePreset.inOneHour], DateTime(2025, 11, 13, 15, 30));
      expect(presets[SchedulePreset.thisEvening], DateTime(2025, 11, 13, 20));
      expect(
        presets[SchedulePreset.tomorrowMorning],
        DateTime(2025, 11, 14, 9),
      );
      expect(presets[SchedulePreset.nextWeek], DateTime(2025, 11, 17, 9));
    });

    test('in one hour rounds up', () {
      final presets = ScheduleRules.presets(DateTime(2025, 11, 13, 14, 31, 5));
      expect(presets[SchedulePreset.inOneHour], DateTime(2025, 11, 13, 15, 35));
    });

    test('this evening is hidden from 19:00', () {
      expect(
        ScheduleRules.presets(
          DateTime(2025, 11, 13, 18, 59),
        ).containsKey(SchedulePreset.thisEvening),
        isTrue,
      );
      expect(
        ScheduleRules.presets(
          DateTime(2025, 11, 13, 19),
        ).containsKey(SchedulePreset.thisEvening),
        isFalse,
      );
    });

    test('next week on a Monday is seven days ahead', () {
      final presets = ScheduleRules.presets(DateTime(2025, 11, 17, 10));
      expect(presets[SchedulePreset.nextWeek], DateTime(2025, 11, 24, 9));
    });

    test('next week on a Sunday is the next day', () {
      final presets = ScheduleRules.presets(DateTime(2025, 11, 16, 10));
      expect(presets[SchedulePreset.nextWeek], DateTime(2025, 11, 17, 9));
    });
  });

  group('validate', () {
    test('59 seconds ahead is too soon', () {
      expect(
        ScheduleRules.validate(
          thursday.add(const Duration(seconds: 59)),
          thursday,
        ),
        ScheduleValidity.tooSoon,
      );
    });

    test('60 seconds ahead is fine', () {
      expect(
        ScheduleRules.validate(
          thursday.add(const Duration(seconds: 60)),
          thursday,
        ),
        ScheduleValidity.ok,
      );
    });

    test('in the past is too soon', () {
      expect(
        ScheduleRules.validate(
          thursday.subtract(const Duration(hours: 1)),
          thursday,
        ),
        ScheduleValidity.tooSoon,
      );
    });

    test('day 365 is fine, day 366 is too far', () {
      expect(
        ScheduleRules.validate(DateTime(2026, 11, 13, 23, 55), thursday),
        ScheduleValidity.ok,
      );
      expect(
        ScheduleRules.validate(DateTime(2026, 11, 14, 0, 5), thursday),
        ScheduleValidity.tooFar,
      );
    });
  });

  group('wheel', () {
    test('fromWheel builds the local date', () {
      expect(
        ScheduleRules.fromWheel(thursday, day: 2, hour: 9, minuteIndex: 3),
        DateTime(2025, 11, 15, 9, 15),
      );
    });

    test('toWheel inverts fromWheel', () {
      final at = DateTime(2025, 12, 24, 21, 55);
      final wheel = ScheduleRules.toWheel(thursday, at);
      expect(wheel, (day: 41, hour: 21, minuteIndex: 11));
      expect(
        ScheduleRules.fromWheel(
          thursday,
          day: wheel.day,
          hour: wheel.hour,
          minuteIndex: wheel.minuteIndex,
        ),
        at,
      );
    });

    test('day arithmetic across the spring clock change', () {
      final now = DateTime(2026, 3, 28, 12);
      final at = ScheduleRules.fromWheel(now, day: 2, hour: 12, minuteIndex: 0);
      expect(at, DateTime(2026, 3, 30, 12));
      expect(ScheduleRules.toWheel(now, at).day, 2);
    });

    test('toWheel rounds the minute down to its step', () {
      expect(ScheduleRules.toWheel(thursday, DateTime(2025, 11, 13, 16, 7)), (
        day: 0,
        hour: 16,
        minuteIndex: 1,
      ));
    });

    test('initial is one hour ahead on the step grid', () {
      expect(ScheduleRules.initial(thursday), DateTime(2025, 11, 13, 15, 30));
    });
  });

  group('groupByDay', () {
    test('groups by calendar day in ascending order', () {
      final items = [
        DateTime(2025, 11, 15, 9),
        DateTime(2025, 11, 14, 11, 30),
        DateTime(2025, 11, 14, 9),
      ];
      final groups = groupByDay<DateTime>(items, (d) => d);
      expect(groups.map((g) => g.day), [
        DateTime(2025, 11, 14),
        DateTime(2025, 11, 15),
      ]);
      expect(groups.first.items, [
        DateTime(2025, 11, 14, 9),
        DateTime(2025, 11, 14, 11, 30),
      ]);
    });

    test('items without a time form the first group', () {
      final groups = groupByDay<DateTime?>([
        DateTime(2025, 11, 14, 9),
        null,
      ], (d) => d);
      expect(groups.first.day, isNull);
      expect(groups.first.items, [null]);
      expect(groups.last.day, DateTime(2025, 11, 14));
    });
  });
}
