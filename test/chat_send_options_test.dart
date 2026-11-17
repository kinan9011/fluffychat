// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/scheduling/schedule_sheet.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/scheduling/scheduled_content.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(() async {
    await harness.tearDown();
    await AppSettings.sendTypingNotifications.setItem(true);
  });

  ChatController controllerOf(WidgetTester tester) =>
      tester.state<ChatController>(find.byType(ChatPageWithRoom));

  Future<void> resetScheduled(WidgetTester tester) async {
    ScheduledStore.forget(harness.client);
    await tester.runAsync(
      () => DraftStore.of(harness.client).remove(harness.room.id),
    );
    await tester.runAsync(
      () => harness.client.database.cacheCustomObject(
        ScheduledStore.documentKey,
        {'v': 1, 'entries': <Object?>[]},
      ),
    );
  }

  Future<void> typeText(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('chat_input_field')), text);
    await harness.settle(tester, rounds: 2);
  }

  Future<void> holdSend(WidgetTester tester) async {
    await tester.longPress(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 2);
  }

  final badge = find.byKey(const Key('send_options_badge'));

  testWidgets('typing text marks the send button and a hold opens the menu', (
    tester,
  ) async {
    await resetScheduled(tester);
    await harness.open(tester);
    expect(badge, findsNothing);
    await typeText(tester, 'hello');
    expect(badge, findsOneWidget);
    await holdSend(tester);
    expect(find.text('Send without sound'), findsOneWidget);
    expect(find.text('Schedule message'), findsOneWidget);
    expect(find.textContaining('best effort'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 1);
    expect(controllerOf(tester).sendController.text, 'hello');
    await harness.finish(tester);
  });

  testWidgets('a screen reader can long press the send button and hears why', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await resetScheduled(tester);
    await harness.open(tester);
    await typeText(tester, 'hello');
    final data = tester
        .getSemantics(find.byKey(const Key('send_button')))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    final hints = [
      for (final id in data.customSemanticsActionIds ?? <int>[])
        CustomSemanticsAction.getAction(id)!,
    ];
    expect(
      hints.any(
        (a) =>
            a.hint == 'Send options' && a.action == SemanticsAction.longPress,
      ),
      isTrue,
    );
    await harness.finish(tester);
    handle.dispose();
  });

  testWidgets('the badge follows the text, not only empty or not', (
    tester,
  ) async {
    await resetScheduled(tester);
    await harness.open(tester);
    await typeText(tester, 'hello');
    expect(badge, findsOneWidget);
    await typeText(tester, '/me waves');
    expect(badge, findsNothing);
    await typeText(tester, 'hello again');
    expect(badge, findsOneWidget);
    await harness.finish(tester);
  });

  group('a direct chat', () {
    const partner = '@mara:example.org';

    setUp(() async {
      harness.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          partner: [harness.room.id],
        },
      );
    });
    tearDown(() {
      harness.client.accountData.remove('m.direct');
      // ignore: deprecated_member_use
      harness.client.presences.remove(partner);
    });

    testWidgets('the menu opens at once and asks the network nothing', (
      tester,
    ) async {
      await resetScheduled(tester);
      await harness.open(tester);
      await typeText(tester, 'hello');
      await holdSend(tester);
      expect(find.text('Schedule message'), findsOneWidget);
      expect(find.textContaining('is online'), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('a cached offline partner adds the when online row', (
      tester,
    ) async {
      await tester.runAsync(
        () => harness.client.database.storePresence(
          partner,
          CachedPresence.fromJson({
            'user_id': partner,
            'presence': 'offline',
            'last_active_timestamp':
                DateTime.now().millisecondsSinceEpoch - 3600000,
          }),
        ),
      );
      await resetScheduled(tester);
      await harness.open(tester);
      await typeText(tester, 'hello');
      await holdSend(tester);
      expect(find.textContaining('is online'), findsOneWidget);
      await harness.finish(tester);
    });
  });

  testWidgets('a command offers no send options', (tester) async {
    await resetScheduled(tester);
    await harness.open(tester);
    await typeText(tester, '/me waves');
    expect(badge, findsNothing);
    await holdSend(tester);
    expect(find.text('Schedule message'), findsNothing);
    expect(controllerOf(tester).sendController.text, '/me waves');
    await harness.finish(tester);
  });

  testWidgets('send without sound sends the flag and clears the composer', (
    tester,
  ) async {
    await resetScheduled(tester);
    await harness.open(tester);
    await typeText(tester, 'psst');
    final before = controllerOf(tester).timeline!.events.length;
    await holdSend(tester);
    await tester.tap(find.text('Send without sound'));
    await harness.settle(tester, rounds: 12);
    final events = controllerOf(tester).timeline!.events;
    expect(events.length, before + 1);
    final sent = events.firstWhere((e) => e.content['body'] == 'psst').content;
    expect(sent[ScheduledContent.silentKey], true);
    expect(controllerOf(tester).sendController.text, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('schedule stores the message and clears the composer', (
    tester,
  ) async {
    await resetScheduled(tester);
    await harness.open(tester);
    await typeText(tester, 'later');
    await holdSend(tester);
    await tester.tap(find.text('Schedule message'));
    await harness.settle(tester, rounds: 4);
    expect(find.byKey(const ValueKey('schedule_confirm')), findsOneWidget);
    expect(find.textContaining('must be running'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
    );
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.byKey(const ValueKey('schedule_confirm')));
    await harness.settle(tester, rounds: 8);
    final store = ScheduledStore.of(harness.client);
    await tester.runAsync(() => store.ready);
    final entry = store.entries().single;
    expect(entry.content['body'], 'later');
    expect(entry.mode, ScheduledMode.device);
    expect(entry.sendAt!.hour, 9);
    expect(controllerOf(tester).sendController.text, isEmpty);
    expect(find.textContaining('Scheduled for'), findsOneWidget);
    expect(find.byKey(const Key('composer_scheduled_button')), findsOneWidget);
    expect(
      tester.getRect(find.textContaining('Scheduled for')).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('composer_scheduled_button'))).top,
      ),
      reason: 'the confirmation must not cover the composer buttons',
    );
    await harness.finish(tester);
  });

  testWidgets('a refused schedule keeps the text and says why', (tester) async {
    await resetScheduled(tester);
    final store = (await tester.runAsync(() async {
      final store = ScheduledStore.of(harness.client);
      await store.ready;
      for (var i = 0; i < ScheduledStore.maxEntries; i++) {
        await store.put(
          ScheduledEntry(
            id: 'entry-${i.toString().padLeft(4, '0')}',
            roomId: '!other:example.org',
            mode: ScheduledMode.device,
            sendAt: DateTime.now().add(const Duration(days: 30)),
            createdAt: DateTime.now(),
            content: const {'msgtype': 'm.text', 'body': 'x'},
          ),
        );
      }
      return store;
    }))!;
    await harness.open(tester);
    await typeText(tester, 'too many');
    await holdSend(tester);
    await tester.tap(find.text('Schedule message'));
    await harness.settle(tester, rounds: 4);
    await tester.tap(
      find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
    );
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.byKey(const ValueKey('schedule_confirm')));
    await harness.settle(tester, rounds: 8);
    expect(find.textContaining('too many scheduled messages'), findsOneWidget);
    expect(controllerOf(tester).sendController.text, 'too many');
    expect(store.entries(), hasLength(ScheduledStore.maxEntries));
    await harness.finish(tester);
  });

  testWidgets('the overflow menu opens the scheduled messages', (tester) async {
    await resetScheduled(tester);
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.text('Scheduled messages'));
    await harness.settle(tester, rounds: 6);
    expect(find.byKey(const Key('scheduled_messages_page')), findsOneWidget);
    expect(find.text('No scheduled messages'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets(
    'on a phone the whole sheet shows, the button needs no scrolling',
    (tester) async {
      await resetScheduled(tester);
      await harness.open(tester, width: 411, height: 914);
      await typeText(tester, 'phone');
      await holdSend(tester);
      await tester.tap(find.text('Schedule message'));
      await harness.settle(tester, rounds: 4);
      final rect = tester.getRect(
        find.byKey(const ValueKey('schedule_confirm')),
      );
      final screen = tester.view.physicalSize;
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(screen.height));
      expect(
        tester.getRect(find.byType(ScheduleSheet)).bottom,
        closeTo(screen.height, 1),
      );
      await tester.tap(find.byKey(const ValueKey('schedule_close')));
      await harness.settle(tester, rounds: 2);
      await harness.finish(tester);
    },
  );

  testWidgets('the sheet is usable on a small screen with the keyboard open', (
    tester,
  ) async {
    await resetScheduled(tester);
    await harness.open(tester, width: 360, height: 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetViewInsets);
    await typeText(tester, 'small screen');
    await holdSend(tester);
    await tester.tap(find.text('Schedule message'));
    await harness.settle(tester, rounds: 4);
    expect(tester.takeException(), isNull);
    final confirm = find.byKey(const ValueKey('schedule_confirm'));
    final sheetScroll = find
        .descendant(
          of: find.byType(ScheduleSheet),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.scrollUntilVisible(
      confirm,
      40,
      scrollable: find
          .descendant(of: sheetScroll, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pump();
    final rect = tester.getRect(confirm);
    final visibleBottom =
        tester.view.physicalSize.height - tester.view.viewInsets.bottom;
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(
      rect.bottom,
      lessThanOrEqualTo(visibleBottom),
      reason: 'the confirm button must not sit under the keyboard',
    );
    expect(rect.height, 54);
    await tester.tap(find.byKey(const ValueKey('schedule_close')));
    await harness.settle(tester, rounds: 2);
    expect(controllerOf(tester).sendController.text, 'small screen');
    await harness.finish(tester);
  });
}
