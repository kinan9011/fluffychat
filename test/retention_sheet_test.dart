// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/retention_sheet.dart';
import 'package:fluffychat/utils/retention/retention_labels.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/golden.dart';
import 'utils/recording_api.dart';
import 'utils/test_client.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(() async {
    harness.room.states.remove(RetentionPolicy.eventType);
    harness.room.states.remove(EventTypes.RoomPowerLevels);
    await harness.tearDown();
  });

  Future<void> openSheet(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
  }) async {
    await harness.open(tester, width: width, height: height);
    unawaited(
      showRetentionSheet(
        tester.element(find.byType(ChatPageWithRoom)),
        harness.room,
      ),
    );
    await harness.settle(tester, rounds: 3);
    api.clear();
  }

  RetentionSheetController sheet(WidgetTester tester) =>
      tester.state<RetentionSheetController>(find.byType(RetentionSheet));

  void setPolicy(Map<String, Object?> content) => harness.room.setState(
    Event(
      type: RetentionPolicy.eventType,
      stateKey: '',
      content: content,
      room: harness.room,
      eventId: r'$retention:example.org',
      senderId: harness.client.userID!,
      originServerTs: DateTime.now(),
    ),
  );

  Future<void> waitForState(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      if (api.requests('/state/m.room.retention').isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<InkWell>(find.byKey(const ValueKey('retention_save')))
          .onTap !=
      null;

  testWidgets('the five choices and the honest note are there', (tester) async {
    await openSheet(tester);
    for (final key in [
      'retention_off',
      'retention_1',
      'retention_7',
      'retention_30',
      'retention_custom',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.textContaining('Hiding is not deleting'), findsOneWidget);
    expect(
      find.textContaining('hidden in this chat on this device after the timer'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('retention_server_note')), findsOneWidget);
    expect(find.textContaining('shows hidden messages again'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('Save is disabled until the choice changes', (tester) async {
    await openSheet(tester);
    expect(saveEnabled(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('retention_1')));
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('retention_off')));
    await tester.pump();
    expect(saveEnabled(tester), isFalse);
    await harness.finish(tester);
  });

  testWidgets('one day is written with the exact content', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('retention_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('retention_save')));
    await waitForState(tester);
    final puts = api.requests('/state/m.room.retention', method: 'PUT');
    expect(puts, hasLength(1));
    expect(puts.single.json, {
      'max_lifetime': 86400000,
      'expire_on_clients': true,
    });
    await harness.finish(tester);
  });

  testWidgets('a week and a month', (tester) async {
    for (final entry in {'retention_7': 7, 'retention_30': 30}.entries) {
      await openSheet(tester);
      await tester.tap(find.byKey(ValueKey(entry.key)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('retention_save')));
      await waitForState(tester);
      final body =
          api.requests('/state/m.room.retention', method: 'PUT').single.json!
              as Map;
      expect(body['max_lifetime'], entry.value * 86400000);
      await harness.finish(tester);
    }
  });

  testWidgets('off writes an empty content', (tester) async {
    setPolicy(RetentionPolicy.contentFor(const Duration(days: 7)));
    await openSheet(tester);
    expect(tester.widget<Text>(find.text('1 week').first).data, '1 week');
    await tester.tap(find.byKey(const ValueKey('retention_off')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('retention_save')));
    await waitForState(tester);
    expect(
      api.requests('/state/m.room.retention', method: 'PUT').single.json,
      isEmpty,
    );
    await harness.finish(tester);
  });

  testWidgets('custom days stay between 1 and 365', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('retention_custom')));
    await tester.pump();
    final c = sheet(tester);
    c.setCustomDays(0);
    await tester.pump();
    expect(c.customDays, 1);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('retention_minus')))
          .onPressed,
      isNull,
    );
    c.setCustomDays(9999);
    await tester.pump();
    expect(c.customDays, 365);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('retention_plus')))
          .onPressed,
      isNull,
    );
    c.setCustomDays(90);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('retention_save')));
    await waitForState(tester);
    final body =
        api.requests('/state/m.room.retention', method: 'PUT').single.json!
            as Map;
    expect(body['max_lifetime'], 90 * 86400000);
    await harness.finish(tester);
  });

  testWidgets('without the right to change settings it is read only', (
    tester,
  ) async {
    harness.room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        stateKey: '',
        content: {
          'users': {harness.client.userID!: 0},
          'state_default': 50,
        },
        room: harness.room,
        eventId: r'$pl:example.org',
        senderId: '@alice:example.com',
        originServerTs: DateTime.now(),
      ),
    );
    await openSheet(tester);
    expect(
      find.byKey(const ValueKey('retention_no_permission')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('retention_save')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('retention_1')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(sheet(tester).selected, isNull);
    await harness.finish(tester);
  });

  testWidgets('on a small screen with the keyboard open Save is reachable', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 150);
    addTearDown(tester.view.resetViewInsets);
    await openSheet(tester, width: 320, height: 480);
    await tester.tap(find.byKey(const ValueKey('retention_1')));
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey('retention_save')));
    expect(rect.bottom, lessThanOrEqualTo(480 - 150 + 1));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  group('a rule set elsewhere', () {
    const foreign = {'max_lifetime': 86400000, 'min_lifetime': 5};

    testWidgets('is said, never shown as Off, and Save stays off', (
      tester,
    ) async {
      setPolicy(foreign);
      await openSheet(tester);
      expect(
        find.text(
          'This chat has a message-history rule set by the server or another '
          "app; this app doesn't hide messages for it.",
        ),
        findsOneWidget,
      );
      expect(sheet(tester).unset, isTrue);
      final off = find.descendant(
        of: find.byKey(const ValueKey('retention_off')),
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(off, findsNothing);
      expect(saveEnabled(tester), isFalse);
      await harness.finish(tester);
    });

    testWidgets('choosing Off replaces only the keys of this app', (
      tester,
    ) async {
      setPolicy(foreign);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('retention_off')));
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('retention_save')));
      await waitForState(tester);
      expect(
        api.requests('/state/m.room.retention', method: 'PUT').single.json,
        {'min_lifetime': 5},
      );
      await harness.finish(tester);
    });

    testWidgets('choosing a timer keeps the keys it does not know', (
      tester,
    ) async {
      setPolicy(foreign);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('retention_7')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('retention_save')));
      await waitForState(tester);
      expect(
        api.requests('/state/m.room.retention', method: 'PUT').single.json,
        {
          'min_lifetime': 5,
          'max_lifetime': 7 * 86400000,
          'expire_on_clients': true,
        },
      );
      await harness.finish(tester);
    });

    testWidgets('no such note when there is no rule or one that is applied', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.textContaining('set by the server'), findsNothing);
      expect(sheet(tester).unset, isFalse);
      await harness.finish(tester);
    });
  });

  group('server note', () {
    late L10n l10n;

    setUp(() async => l10n = await L10n.delegate.load(const Locale('en')));

    test('says what is known and never more', () {
      expect(
        retentionServerNote(l10n, FeatureSupport.supported),
        'Your server can also delete them, if its admin turned that on.',
      );
      expect(
        retentionServerNote(l10n, FeatureSupport.unsupported),
        "Your server doesn't remove messages by itself.",
      );
      expect(
        retentionServerNote(l10n, FeatureSupport.unknown),
        "We couldn't check whether your server removes messages.",
      );
      expect(
        retentionServerNote(l10n, FeatureSupport.partial),
        retentionServerNote(l10n, FeatureSupport.unknown),
      );
    });

    test('no copy claims that anything is deleted for everyone', () {
      final texts = [
        l10n.retentionHonestNote,
        l10n.retentionOffNote,
        for (final s in FeatureSupport.values) retentionServerNote(l10n, s),
      ].join(' ').toLowerCase();
      expect(texts, contains('not deleting'));
      expect(texts, isNot(contains('for everyone')));
      expect(texts, isNot(contains('erase')));
    });

    test('durations read well', () {
      expect(formatRetention(l10n, const Duration(days: 1)), '1 day');
      expect(formatRetention(l10n, const Duration(days: 2)), '2 days');
      expect(formatRetention(l10n, const Duration(days: 7)), '1 week');
      expect(formatRetention(l10n, const Duration(days: 30)), '1 month');
      expect(formatRetention(l10n, const Duration(days: 90)), '90 days');
      expect(formatRetention(l10n, const Duration(hours: 5)), '5 hours');
      expect(formatRetention(l10n, const Duration(hours: 1)), '1 hour');
    });
  });

  testGoldens('the sheet', (tester) async {
    final client = (await tester.runAsync(prepareTestClient))!;
    final room = client.rooms.firstWhere(
      (r) => r.membership == Membership.join,
    );
    for (final variant in goldenVariants) {
      await pumpGoldenWidget(
        tester,
        RetentionSheet(
          key: ValueKey(variant.suffix),
          room: room,
          serverSupport: FeatureSupport.unknown,
        ),
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: variant.locale,
        size: const Size(400, 900),
      );
      await tester.tap(find.byKey(const ValueKey('retention_custom')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/retention_sheet_${variant.suffix}.png'),
      );
    }
    await tester.runAsync(() => client.dispose(closeDatabase: true));
  });

  group('service message', () {
    late L10n l10n;
    late Room room;

    setUp(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
      room = harness.client.rooms.firstWhere(
        (r) => r.membership == Membership.join,
      );
    });

    Event state(Map<String, Object?> content) => Event(
      type: RetentionPolicy.eventType,
      stateKey: '',
      content: content,
      room: room,
      eventId: r'$s:example.org',
      senderId: '@alice:example.com',
      originServerTs: DateTime.now(),
    );

    test('a timer is announced with its length', () {
      expect(
        retentionServiceText(
          l10n,
          state(RetentionPolicy.contentFor(const Duration(days: 2))),
        ),
        endsWith('set messages to disappear after 2 days'),
      );
    });

    test('empty content reads as turned off', () {
      expect(
        retentionServiceText(l10n, state(<String, Object?>{})),
        endsWith('turned off disappearing messages'),
      );
    });

    test('a rule this app does not apply is never reported as turned off', () {
      for (final content in <Map<String, Object?>>[
        {'max_lifetime': 5, 'expire_on_clients': true},
        {'max_lifetime': 86400000},
        {'max_lifetime': 86400000, 'expire_on_clients': false},
        {'max_lifetime': 1000 * 86400000 * 365 * 6, 'expire_on_clients': true},
        {'min_lifetime': 5},
      ]) {
        final text = retentionServiceText(l10n, state(content));
        expect(text, endsWith('changed how long messages are kept'));
        expect(text, isNot(contains('turned off')));
        expect(text, isNot(contains('disappear')));
      }
    });
  });
}
