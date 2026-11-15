// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_jump_buttons.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Event mention(Room room, String id, {List<String>? users}) => Event(
    type: EventTypes.Message,
    content: {
      'msgtype': MessageTypes.Text,
      'body': 'plain text',
      'm.mentions': {
        'user_ids': users ?? [room.client.userID!],
      },
    },
    room: room,
    eventId: id,
    senderId: '@bob:example.org',
    originServerTs: DateTime.now(),
  );

  Finder badge(String text) => find.descendant(
    of: find.byKey(ChatJumpButtons.mentionKey),
    matching: find.text(text),
  );

  ChatController controllerOf(WidgetTester tester) =>
      tester.state<ChatController>(find.byType(ChatPageWithRoom));

  testWidgets('no mention, no jump button', (tester) async {
    await harness.open(tester);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a mention shows the button, taps walk through the mentions and '
      'send nothing', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final events = controller.timeline!.events;
    events.insert(0, mention(harness.room, r'$m2:example.org'));
    events.insert(1, mention(harness.room, r'$m1:example.org'));
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsOneWidget);
    expect(badge('2'), findsOneWidget);

    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.byKey(ChatJumpButtons.mentionKey));
    await harness.settle(tester, rounds: 3);
    expect(controller.scrollToEventIdMarker, r'$m1:example.org');
    expect(badge('1'), findsOneWidget);
    await tester.tap(find.byKey(ChatJumpButtons.mentionKey));
    await harness.settle(tester, rounds: 3);
    expect(controller.scrollToEventIdMarker, r'$m2:example.org');
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);

    final sent = FakeMatrixApi.calledEndpoints.keys.where(
      (path) =>
          path.contains('receipt') ||
          path.contains('read_markers') ||
          path.contains('typing') ||
          path.contains('presence'),
    );
    expect(sent, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a mention of somebody else shows no button', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    controller.timeline!.events.insert(
      0,
      mention(harness.room, r'$other:example.org', users: ['@x:example.org']),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('mentions the server counts but that are not loaded show the '
      'button, and a tap loads older history', (tester) async {
    await harness.open(tester, highlightCount: 3);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsOneWidget);
    expect(badge('3'), findsOneWidget);
    final controller = controllerOf(tester);
    FakeMatrixApi.calledEndpoints.clear();
    await controller.jumpToNextMention();
    await harness.settle(tester, rounds: 3);
    final sent = FakeMatrixApi.calledEndpoints.keys.where(
      (path) =>
          path.contains('receipt') ||
          path.contains('read_markers') ||
          path.contains('typing'),
    );
    expect(sent, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a loaded mention is not counted twice', (tester) async {
    await harness.open(tester, highlightCount: 1);
    final controller = controllerOf(tester);
    controller.timeline!.events.insert(
      0,
      mention(harness.room, r'$m1:example.org'),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(badge('1'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a server count nothing local can match does not leave a dead '
      'button after one tap (REV M-3)', (tester) async {
    await harness.open(tester, highlightCount: 2);
    expect(badge('2'), findsOneWidget);
    final controller = controllerOf(tester);
    FakeMatrixApi.calledEndpoints.clear();
    await tester.runAsync(controller.jumpToNextMention);
    await harness.settle(tester, rounds: 3);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    final history = FakeMatrixApi.calledEndpoints.keys.where(
      (path) => path.contains('/messages'),
    );
    expect(history.length, lessThanOrEqualTo(5));
    await harness.finish(tester);
  });

  testWidgets('a new server count brings the button back (REV M-3)', (
    tester,
  ) async {
    await harness.open(tester, highlightCount: 2);
    final controller = controllerOf(tester);
    await tester.runAsync(controller.jumpToNextMention);
    await harness.settle(tester, rounds: 3);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    harness.room.highlightCount = 3;
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(badge('3'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a mention that only becomes readable later is found after the '
      'next update (REV m13)', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = mention(harness.room, r'$late:example.org', users: []);
    controller.timeline!.events.insert(0, event);
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    event.content['m.mentions'] = {
      'user_ids': [harness.room.client.userID],
    };
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    expect(badge('1'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a negative server count shows no button (SEC I3)', (
    tester,
  ) async {
    await harness.open(tester, highlightCount: -5);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a huge server count shows 99+ and never more (SEC I3)', (
    tester,
  ) async {
    await harness.open(tester, highlightCount: 1 << 40);
    expect(badge('99+'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a tap that finds no older mention says so (REV N4)', (
    tester,
  ) async {
    await harness.open(tester, highlightCount: 2);
    final controller = controllerOf(tester);
    await tester.runAsync(controller.jumpToNextMention);
    await harness.settle(tester, rounds: 3);
    expect(find.text('No older mention found yet'), findsOneWidget);
    await harness.finish(tester);
  });
}
