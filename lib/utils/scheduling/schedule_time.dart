// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

enum SchedulePreset { inOneHour, thisEvening, tomorrowMorning, nextWeek }

enum ScheduleValidity { ok, tooSoon, tooFar }

/// Time rules of the schedule picker. Every date is built with the local
/// `DateTime` constructor so that clock changes never shift the wall time.
abstract class ScheduleRules {
  static const minLead = Duration(minutes: 1);
  static const maxDays = 365;
  static const minuteStep = 5;
  static const _eveningCutoffHour = 19;

  static DateTime roundUpToStep(DateTime t) {
    final floored = DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute - t.minute % minuteStep,
    );
    if (floored == t) return t;
    return DateTime(
      floored.year,
      floored.month,
      floored.day,
      floored.hour,
      floored.minute + minuteStep,
    );
  }

  static DateTime _inOneHour(DateTime now) =>
      DateTime(now.year, now.month, now.day, now.hour + 1, now.minute);

  static Map<SchedulePreset, DateTime> presets(DateTime now) {
    final daysToMonday = (DateTime.monday - now.weekday) % 7;
    return {
      SchedulePreset.inOneHour: roundUpToStep(_inOneHour(now)),
      if (now.hour < _eveningCutoffHour)
        SchedulePreset.thisEvening: DateTime(now.year, now.month, now.day, 20),
      SchedulePreset.tomorrowMorning: DateTime(
        now.year,
        now.month,
        now.day + 1,
        9,
      ),
      SchedulePreset.nextWeek: DateTime(
        now.year,
        now.month,
        now.day + (daysToMonday == 0 ? 7 : daysToMonday),
        9,
      ),
    };
  }

  static ScheduleValidity validate(DateTime at, DateTime now) {
    if (at.isBefore(now.add(minLead))) return ScheduleValidity.tooSoon;
    final lastDay = DateTime(now.year, now.month, now.day + maxDays);
    final day = DateTime(at.year, at.month, at.day);
    return day.isAfter(lastDay) ? ScheduleValidity.tooFar : ScheduleValidity.ok;
  }

  static DateTime fromWheel(
    DateTime now, {
    required int day,
    required int hour,
    required int minuteIndex,
  }) => DateTime(
    now.year,
    now.month,
    now.day + day,
    hour,
    minuteIndex * minuteStep,
  );

  static ({int day, int hour, int minuteIndex}) toWheel(
    DateTime now,
    DateTime at,
  ) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final target = DateTime.utc(at.year, at.month, at.day);
    return (
      day: target.difference(today).inDays,
      hour: at.hour,
      minuteIndex: at.minute ~/ minuteStep,
    );
  }

  static DateTime initial(DateTime now) => roundUpToStep(_inOneHour(now));
}

/// Groups by local calendar day in ascending order. Items without a time form
/// the first group (`day == null`).
List<({DateTime? day, List<T> items})> groupByDay<T>(
  Iterable<T> items,
  DateTime? Function(T) at,
) {
  final sorted = items.toList()
    ..sort((a, b) {
      final left = at(a);
      final right = at(b);
      if (left == null || right == null) {
        return left == right ? 0 : (left == null ? -1 : 1);
      }
      return left.compareTo(right);
    });
  final groups = <({DateTime? day, List<T> items})>[];
  for (final item in sorted) {
    final time = at(item);
    final day = time == null ? null : DateTime(time.year, time.month, time.day);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.items.add(item);
      continue;
    }
    groups.add((day: day, items: [item]));
  }
  return groups;
}
