// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/events/utd_bubble_content.dart';
import 'package:fluffychat/pages/chat/message_action_runner.dart';
import 'package:fluffychat/pages/chat/utd_why_sheet.dart';
import 'package:fluffychat/utils/chat/message_actions.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

/// An undecryptable event keeps the original encrypted content, so it must
/// never reach Forward, Copy, Edit or Pin (SEC L1, S-1).
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

  var counter = 0;
  Event utdEvent() => Event(
    type: EventTypes.Encrypted,
    content: {
      'msgtype': MessageTypes.BadEncrypted,
      'body': 'ciphertext-body',
      'algorithm': 'm.megolm.v1.aes-sha2',
      'ciphertext': 'secret-ciphertext',
      'can_request_session': true,
    },
    room: harness.room,
    eventId: '\$utd${counter++}:example.org',
    senderId: harness.client.userID!,
    originServerTs: DateTime(2030, 1, 1, 12, 41),
    status: EventStatus.synced,
  );

  Event plain(String body) => Event(
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': body},
    room: harness.room,
    eventId: '\$plain${counter++}:example.org',
    senderId: '@bob:example.org',
    originServerTs: DateTime(2030, 1, 1, 12, 40),
    status: EventStatus.synced,
  );

  Future<ChatController> open(WidgetTester tester, List<Event> events) async {
    await harness.open(tester);
    final controller = tester.state<ChatController>(
      find.byType(ChatPageWithRoom),
    );
    controller.timeline!.events.insertAll(0, events);
    controller.updateView();
    await harness.settle(tester, rounds: 3);
    return controller;
  }

  testWidgets('no entry point selects an undecryptable message', (
    tester,
  ) async {
    final utd = utdEvent();
    final controller = await open(tester, [utd]);
    controller.onSelectMessage(utd);
    expect(controller.selectedEvents, isEmpty);
    controller.selectOnly(utd);
    expect(controller.selectedEvents, isEmpty);
    expect(
      availableMessageActions(messageActionContext(controller, utd)),
      isNot(contains(MessageAction.select)),
    );
    await harness.finish(tester);
  });

  testWidgets('in select mode an undecryptable message has no check circle', (
    tester,
  ) async {
    final utd = utdEvent();
    final readable = plain('hello there');
    final controller = await open(tester, [utd, readable]);
    controller.selectOnly(readable);
    await harness.settle(tester, rounds: 2);
    Finder circle(String text) => find.descendant(
      of: find.ancestor(of: find.text(text), matching: find.byType(Message)),
      matching: find.byTooltip('Select'),
    );
    expect(circle('hello there'), findsOneWidget);
    expect(circle('Waiting for this message'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a long press on an undecryptable message offers no Select', (
    tester,
  ) async {
    await open(tester, [utdEvent()]);
    await tester.longPress(find.text('Waiting for this message'));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsOneWidget);
    expect(find.text('Select'), findsNothing);
    await harness.finish(tester);
  });

  group('selection-driven actions refuse one that got in anyway', () {
    testWidgets('copy leaves it out', (tester) async {
      final utd = utdEvent();
      final readable = plain('hello there');
      final controller = await open(tester, [utd, readable]);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      controller.selectedEvents
        ..add(readable)
        ..add(utd);
      controller.copyEventsAction();
      expect(copied, 'hello there');
      await harness.finish(tester);
    });

    testWidgets('edit and pin are refused', (tester) async {
      final utd = utdEvent();
      final controller = await open(tester, [utd]);
      expect(controller.canEditEvent(utd), isFalse);
      expect(controller.canPinEvent(utd), isFalse);
      await harness.finish(tester);
    });

    testWidgets('forward shares only the readable messages', (tester) async {
      final utd = utdEvent();
      final readable = plain('hello there');
      final controller = await open(tester, [utd, readable]);
      controller.selectedEvents
        ..add(readable)
        ..add(utd);
      unawaited(controller.forwardEventsAction());
      await harness.settle(tester, rounds: 3);
      final items = tester
          .widget<ShareScaffoldDialog>(find.byType(ShareScaffoldDialog))
          .items;
      expect(items, hasLength(1));
      final shared = (items.single as ContentShareItem).value;
      expect(shared.toString(), isNot(contains('secret-ciphertext')));
      await harness.finish(tester);
    });

    testWidgets('forward with only an undecryptable one shares nothing', (
      tester,
    ) async {
      final utd = utdEvent();
      final controller = await open(tester, [utd]);
      controller.selectedEvents.add(utd);
      await controller.forwardEventsAction();
      await harness.settle(tester, rounds: 2);
      expect(find.byType(ShareScaffoldDialog), findsNothing);
      await harness.finish(tester);
    });
  });

  testWidgets('Enter on "Why?" opens the sheet, not the message menu '
      '(REV N1)', (tester) async {
    await open(tester, [utdEvent()]);
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      final onWhy =
          focused?.findAncestorWidgetOfExactType<UtdBubbleContent>() != null;
      if (onWhy) break;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await harness.settle(tester, rounds: 3);
    expect(find.byType(UtdWhySheet), findsOneWidget);
    expect(find.byType(GlassMenuCard), findsNothing);
    await harness.finish(tester);
  });

  for (final group in [false, true]) {
    testWidgets('entering select mode keeps the bubble content alive '
        '(${group ? 'group' : 'direct'} chat, REV N2)', (tester) async {
      final direct = harness.client.accountData['m.direct'];
      if (group) {
        harness.client.accountData['m.direct'] = BasicEvent(
          type: 'm.direct',
          content: const {},
        );
        addTearDown(() => harness.client.accountData['m.direct'] = direct!);
      }
      final first = plain('first one');
      final second = plain('second one');
      final controller = await open(tester, [second, first]);
      final before = tester.element(find.text('first one'));
      controller.selectOnly(second);
      await harness.settle(tester, rounds: 3);
      expect(tester.element(find.text('first one')), same(before));
      controller.clearSelectedEvents();
      await harness.settle(tester, rounds: 3);
      expect(tester.element(find.text('first one')), same(before));
      await harness.finish(tester);
    });
  }
}
