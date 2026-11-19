// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/pages/chat/scheduling/schedule_sheet.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';

import 'utils/golden.dart';

final thursday = DateTime(2025, 11, 13, 14, 30);

Widget sheet({
  ScheduledMode mode = ScheduledMode.server,
  bool encrypted = false,
  DateTime? initial,
  DateTime Function()? now,
}) => Align(
  alignment: Alignment.bottomCenter,
  child: ScheduleSheet(
    preview: 'Standup moved to 10:00, same link',
    mode: mode,
    encrypted: encrypted,
    initial: initial,
    now: now ?? () => thursday,
  ),
);

Finder get confirm => find.byKey(const ValueKey('schedule_confirm'));

String confirmLabel(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: confirm, matching: find.byType(Text)),
  );
  return texts.single.data!;
}

Future<void> ready(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

void main() {
  const size = Size(400, 760);

  testWidgets('opens one hour ahead on the five minute grid', (tester) async {
    await pumpGoldenWidget(tester, sheet(), size: size);
    expect(confirmLabel(tester), 'Schedule for Thu, Nov 13, 3:30 PM');
  });

  testWidgets('a start time in the past falls back to one hour ahead', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      sheet(initial: thursday.subtract(const Duration(days: 1))),
      size: size,
    );
    expect(confirmLabel(tester), 'Schedule for Thu, Nov 13, 3:30 PM');
  });

  testWidgets('a given start time is the starting point', (tester) async {
    await pumpGoldenWidget(
      tester,
      sheet(initial: DateTime(2025, 11, 20, 9)),
      size: size,
    );
    expect(confirmLabel(tester), 'Schedule for Thu, Nov 20, 9:00 AM');
  });

  testWidgets('a preset moves the wheels and the button', (tester) async {
    await pumpGoldenWidget(tester, sheet(), size: size);
    await tester.tap(
      find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
    );
    await tester.pumpAndSettle();
    expect(confirmLabel(tester), 'Schedule for Fri, Nov 14, 9:00 AM');
    await tester.tap(find.byKey(const ValueKey('schedule_preset_nextWeek')));
    await tester.pumpAndSettle();
    expect(confirmLabel(tester), 'Schedule for Mon, Nov 17, 9:00 AM');
  });

  testWidgets('the chosen preset is marked and a wheel move clears it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(tester, sheet(), size: size);
    bool selected(String key) => tester
        .widget<Semantics>(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .selected!;
    await tester.tap(find.byKey(const ValueKey('schedule_preset_thisEvening')));
    await tester.pumpAndSettle();
    expect(selected('schedule_preset_thisEvening'), isTrue);
    await tester.drag(
      find.byKey(const ValueKey('schedule_wheel_hour')),
      const Offset(0, -AppSchedule.wheelRow),
    );
    await tester.pumpAndSettle();
    expect(selected('schedule_preset_thisEvening'), isFalse);
    handle.dispose();
  });

  testWidgets('this evening is not offered from 19:00', (tester) async {
    await pumpGoldenWidget(
      tester,
      sheet(now: () => DateTime(2025, 11, 13, 19, 30)),
      size: size,
    );
    expect(
      find.byKey(const ValueKey('schedule_preset_thisEvening')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
      findsOneWidget,
    );
  });

  testWidgets('dragging the wheels changes the time', (tester) async {
    await pumpGoldenWidget(tester, sheet(), size: size);
    await tester.drag(
      find.byKey(const ValueKey('schedule_wheel_hour')),
      const Offset(0, -AppSchedule.wheelRow * 2),
    );
    await tester.pumpAndSettle();
    expect(confirmLabel(tester), 'Schedule for Thu, Nov 13, 5:30 PM');
    await tester.drag(
      find.byKey(const ValueKey('schedule_wheel_minute')),
      const Offset(0, -AppSchedule.wheelRow * 3),
    );
    await tester.pumpAndSettle();
    expect(confirmLabel(tester), 'Schedule for Thu, Nov 13, 5:45 PM');
    await tester.drag(
      find.byKey(const ValueKey('schedule_wheel_day')),
      const Offset(0, -AppSchedule.wheelRow),
    );
    await tester.pumpAndSettle();
    expect(confirmLabel(tester), 'Schedule for Fri, Nov 14, 5:45 PM');
  });

  testWidgets('a time less than a minute ahead cannot be confirmed', (
    tester,
  ) async {
    var clock = thursday;
    await pumpGoldenWidget(tester, sheet(now: () => clock), size: size);
    clock = DateTime(2025, 11, 13, 15, 29, 30);
    await tester.tap(confirm);
    await tester.pump();
    expect(find.byKey(const ValueKey('schedule_warning')), findsOneWidget);
    expect(
      find.text('Pick a time at least one minute from now.'),
      findsOneWidget,
    );
    expect(find.byType(ScheduleSheet), findsOneWidget, reason: 'stays open');
  });

  group('as a sheet', () {
    Future<Future<DateTime?>> show(WidgetTester tester) async {
      await pumpGoldenWidget(tester, const SizedBox.expand(), size: size);
      return showScheduleSheet(
        tester.element(find.byType(Scaffold)),
        preview: 'hello',
        mode: ScheduledMode.server,
        encrypted: false,
        now: () => thursday,
      );
    }

    testWidgets('confirm returns the time', (tester) async {
      final result = await show(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(await result, DateTime(2025, 11, 14, 9));
    });

    testWidgets('close returns nothing', (tester) async {
      final result = await show(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule_close')));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('honest copy', () {
    testWidgets('on the server: it sends even when the phone is off', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, sheet(), size: size);
      expect(
        find.textContaining('even if your phone is offline'),
        findsOneWidget,
      );
      expect(find.textContaining('must be running'), findsNothing);
      expect(find.textContaining('before it\'s sent'), findsNothing);
    });

    testWidgets('on this device: it must be running', (tester) async {
      await pumpGoldenWidget(
        tester,
        sheet(mode: ScheduledMode.device, encrypted: true),
        size: size,
      );
      expect(find.textContaining('must be running'), findsOneWidget);
      expect(
        find.textContaining('even if your phone is offline'),
        findsNothing,
      );
      expect(find.textContaining('before it\'s sent'), findsNothing);
    });

    testWidgets('on the server in an encrypted chat: who cannot read it', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, sheet(encrypted: true), size: size);
      expect(
        find.textContaining('even if your phone is offline'),
        findsOneWidget,
      );
      expect(find.textContaining('before it\'s sent'), findsOneWidget);
    });
  });

  testWidgets('touch targets are at least 44 and the button is 54', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, sheet(), size: size);
    expect(
      tester.getSize(find.byKey(const ValueKey('schedule_close'))).shortestSide,
      greaterThanOrEqualTo(44),
    );
    for (final key in ['inOneHour', 'tomorrowMorning', 'nextWeek']) {
      expect(
        tester.getSize(find.byKey(ValueKey('schedule_preset_$key'))).height,
        greaterThanOrEqualTo(44),
      );
    }
    expect(tester.getSize(confirm).height, AppSchedule.primaryButton);
  });

  testWidgets('the wheels are labelled with their value for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(tester, sheet(), size: size);
    final hour = tester.getSemantics(
      find.byKey(const ValueKey('schedule_wheel_hour')),
    );
    expect(hour.label, 'Hour');
    expect(hour.value, '15');
    final minute = tester.getSemantics(
      find.byKey(const ValueKey('schedule_wheel_minute')),
    );
    expect(minute.label, 'Minute');
    expect(minute.value, '30');
    handle.dispose();
  });

  testWidgets('goldens', (tester) async {
    final variants = {
      'server_light': (goldenVariants[0], ScheduledMode.server, false),
      'device_dark': (goldenVariants[1], ScheduledMode.device, false),
      'server_encrypted_rtl': (goldenVariants[2], ScheduledMode.server, true),
    };
    for (final entry in variants.entries) {
      final (variant, mode, encrypted) = entry.value;
      await pumpGoldenWidget(
        tester,
        sheet(mode: mode, encrypted: encrypted),
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: variant.locale,
        size: size,
      );
      await ready(tester);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/schedule_sheet_${entry.key}.png'),
      );
    }
  });
}
