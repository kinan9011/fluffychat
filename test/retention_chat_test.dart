// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/chat_overflow_menu.dart';
import 'package:odango/pages/chat/retention_sheet.dart';
import 'package:odango/utils/retention/retention_policy.dart';

import 'utils/chat_page_harness.dart';
import 'utils/golden.dart';
import 'utils/recording_api.dart';

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
    await harness.tearDown();
  });

  ChatController controllerOf(WidgetTester tester) =>
      tester.state<ChatController>(find.byType(ChatPageWithRoom));

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

  Event message(String id, String body, DateTime at) => Event(
    type: EventTypes.Message,
    content: {'msgtype': 'm.text', 'body': body},
    room: harness.room,
    eventId: id,
    senderId: '@bob:example.org',
    originServerTs: at,
  );

  testWidgets('old messages vanish, new ones stay, nothing is deleted', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    controller.timeline!.events.insert(
      0,
      message(r'$fresh:example.org', 'fresh message', DateTime.now()),
    );
    controller.timeline!.events.insert(
      1,
      message(
        r'$old:example.org',
        'old message',
        DateTime.now().subtract(const Duration(days: 3)),
      ),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(find.text('fresh message'), findsOneWidget);
    expect(find.text('old message'), findsOneWidget);

    api.clear();
    setPolicy(RetentionPolicy.contentFor(const Duration(days: 1)));
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(find.text('fresh message'), findsOneWidget);
    expect(find.text('old message'), findsNothing);
    expect(
      controller.timeline!.events.any((e) => e.eventId == r'$old:example.org'),
      isTrue,
    );
    expect(api.requests('/redact/'), isEmpty);
    expect(api.log.where((r) => r.method == 'DELETE'), isEmpty);
    expect(api.requests('/send/'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the header says when messages disappear', (tester) async {
    setPolicy(RetentionPolicy.contentFor(const Duration(days: 1)));
    await harness.open(tester);
    expect(find.text('Disappear after 1 day'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsWidgets);
    await harness.finish(tester);
  });

  testWidgets('a timer that cannot be applied shows nothing', (tester) async {
    setPolicy({'max_lifetime': 1000, 'expire_on_clients': true});
    await harness.open(tester);
    expect(find.textContaining('Disappear after'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a message that expires while the chat is open disappears', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    setPolicy(RetentionPolicy.contentFor(const Duration(days: 1)));
    controller.timeline!.events.insert(
      0,
      message(
        r'$soon:example.org',
        'about to expire',
        DateTime.now()
            .subtract(const Duration(days: 1))
            .add(const Duration(milliseconds: 1500)),
      ),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 1);
    expect(find.text('about to expire'), findsOneWidget);
    api.clear();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1700)),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('about to expire'), findsNothing);
    expect(api.requests('/redact/'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the retention state event shows as a service message', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    controller.timeline!.events.insert(
      0,
      Event(
        type: RetentionPolicy.eventType,
        stateKey: '',
        content: RetentionPolicy.contentFor(const Duration(days: 7)),
        room: harness.room,
        eventId: r'$state:example.org',
        senderId: '@alice:example.com',
        originServerTs: DateTime.now(),
      ),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(
      find.textContaining('set messages to disappear after 1 week'),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets('the overflow menu opens the sheet', (tester) async {
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 2);
    expect(find.text('Disappearing messages'), findsOneWidget);
    await tester.tap(find.text('Disappearing messages'));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(RetentionSheet), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('the entry is the real overflow action', (tester) async {
    expect(
      chatOverflowActions(
        muted: false,
        canCall: false,
        showDetails: false,
        joined: true,
        left: false,
      ),
      contains(ChatOverflowAction.disappearing),
    );
  });

  testGoldens('header with a timer', (tester) async {
    for (final variant in goldenVariants) {
      setPolicy(RetentionPolicy.contentFor(const Duration(days: 1)));
      await harness.open(
        tester,
        height: 300,
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/chat_header_disappearing_${variant.suffix}.png',
        ),
      );
      await harness.finish(tester);
    }
  });
}
