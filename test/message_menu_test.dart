// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';
import 'package:odango/pages/chat/events/message_focus.dart';
import 'package:odango/pages/chat/events/message_hover_actions.dart';
import 'package:odango/pages/chat/events/reaction_bar.dart';
import 'package:odango/pages/chat/message_action_runner.dart';
import 'package:odango/utils/chat/message_actions.dart';
import 'package:odango/widgets/glass_menu.dart';

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

  var counter = 0;
  Event message(
    String body, {
    String? sender,
    EventStatus status = EventStatus.synced,
  }) => Event(
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': body},
    room: harness.room,
    eventId: '\$m${counter++}:example.org',
    senderId: sender ?? harness.client.userID!,
    originServerTs: DateTime(2030, 1, 1, 12, 41),
    status: status,
  );

  Future<ChatController> openWith(
    WidgetTester tester,
    List<Event> events, {
    double width = 400,
    double height = 900,
  }) async {
    await harness.open(tester, width: width, height: height);
    final controller = controllerOf(tester);
    controller.timeline!.events.insertAll(0, events);
    controller.updateView();
    await harness.settle(tester, rounds: 3);
    return controller;
  }

  Future<void> longPress(WidgetTester tester, String text) async {
    await tester.longPress(find.text(text));
    await harness.settle(tester, rounds: 3);
  }

  List<String> sent() => FakeMatrixApi.calledEndpoints.keys.toList();

  testWidgets(
    'long press opens the reaction bar and the menu, selects nothing',
    (tester) async {
      final controller = await openWith(tester, [message('hello there')]);
      await longPress(tester, 'hello there');
      expect(find.byType(ReactionBar), findsOneWidget);
      for (final label in [
        'Reply',
        'Reply in thread',
        'Edit',
        'Copy to clipboard',
        'Forward',
        'Select',
        'Message info',
        'Report message',
        'Delete for everyone',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(controller.selectedEvents, isEmpty);
      expect(controller.selectMode, isFalse);
      await harness.finish(tester);
    },
  );

  testWidgets('Escape closes the menu and nothing happens', (tester) async {
    final controller = await openWith(tester, [message('hello there')]);
    await longPress(tester, 'hello there');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsNothing);
    expect(controller.selectedEvents, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a reaction is sent once and the menu closes', (tester) async {
    await openWith(tester, [message('hello there')]);
    await longPress(tester, 'hello there');
    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.text('👍'));
    await harness.settle(tester, rounds: 3);
    final reactions = sent().where((path) => path.contains('m.reaction'));
    expect(reactions, hasLength(1));
    expect(find.byType(GlassMenuCard), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('Reply sets the reply and leaves no selection', (tester) async {
    final event = message('hello there', sender: '@bob:example.org');
    final controller = await openWith(tester, [event]);
    await longPress(tester, 'hello there');
    await tester.tap(find.text('Reply'));
    await harness.settle(tester, rounds: 3);
    expect(controller.replyEvent?.eventId, event.eventId);
    expect(controller.selectedEvents, isEmpty);
    await harness.finish(tester);
  });

  testWidgets(
    'Select starts multi-select and the next long press does not open '
    'a menu',
    (tester) async {
      final first = message('first one');
      final second = message('second one');
      final controller = await openWith(tester, [second, first]);
      await longPress(tester, 'first one');
      await tester.tap(find.text('Select'));
      await harness.settle(tester, rounds: 3);
      expect(controller.selectMode, isTrue);
      expect(controller.selectedEvents.single.eventId, first.eventId);
      await tester.longPress(find.text('second one'));
      await harness.settle(tester, rounds: 3);
      expect(find.byType(GlassMenuCard), findsNothing);
      await harness.finish(tester);
    },
  );

  testWidgets('a message that failed to send keeps long press = select', (
    tester,
  ) async {
    final failed = message('did not work', status: EventStatus.error);
    final controller = await openWith(tester, [failed]);
    await longPress(tester, 'did not work');
    expect(find.byType(GlassMenuCard), findsNothing);
    expect(controller.selectedEvents.single.eventId, failed.eventId);
    await harness.finish(tester);
  });

  testWidgets(
    'Delete for everyone asks first and acts on the pressed message',
    (tester) async {
      final other = message('keep me', sender: '@bob:example.org');
      final mine = message('delete me');
      final controller = await openWith(tester, [mine, other]);
      await longPress(tester, 'delete me');
      FakeMatrixApi.calledEndpoints.clear();
      await tester.tap(find.text('Delete for everyone'));
      await harness.settle(tester, rounds: 3);
      expect(sent().where((path) => path.contains('redact')), isEmpty);
      expect(find.text('Delete for everyone'), findsWidgets);
      expect(controller.selectedEvents.single.eventId, mine.eventId);
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester, rounds: 3);
      expect(sent().where((path) => path.contains('redact')), isEmpty);
      expect(controller.selectedEvents, isEmpty);
      await harness.finish(tester);
    },
  );

  testWidgets('desktop: hover shows react, reply and more; right click opens '
      'the menu', (tester) async {
    final controller = await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ], width: 1000);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('hello there')));
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('message_hover_actions')), findsOneWidget);
    expect(find.byType(MessageHoverActions), findsWidgets);

    await mouse.moveTo(Offset.zero);
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('message_hover_actions')), findsNothing);

    await tester.tapAt(
      tester.getCenter(find.text('hello there')),
      buttons: kSecondaryButton,
    );
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsOneWidget);
    expect(controller.selectedEvents, isEmpty);
    await harness.finish(tester);
  });

  Finder hoverButton(String label) => find.descendant(
    of: find.byKey(const Key('message_hover_actions')),
    matching: find.byTooltip(label),
  );

  testWidgets('the hover menu is anchored on the bubble, not on the sender '
      'name above it (REV m1)', (tester) async {
    final direct = harness.client.accountData['m.direct'];
    harness.client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: const {},
    );
    addTearDown(() => harness.client.accountData['m.direct'] = direct!);
    await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ], width: 1000);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('hello there')));
    await harness.settle(tester, rounds: 2);
    await tester.tap(hoverButton('More options'));
    await harness.settle(tester, rounds: 3);
    final bubble = tester.getRect(
      find
          .ancestor(
            of: find.text('hello there'),
            matching: find.byType(MessageBubble),
          )
          .first,
    );
    expect(
      tester.getRect(find.byType(GlassMenuCard)).bottom,
      closeTo(bubble.top - 8, 2),
    );
    await harness.finish(tester);
  });

  testWidgets('the hover buttons are 44 x 44 (REV m15)', (tester) async {
    await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ], width: 1000);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('hello there')));
    await harness.settle(tester, rounds: 2);
    for (final label in ['More options', 'Reply', 'More reactions']) {
      final size = tester.getSize(hoverButton(label));
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
    await harness.finish(tester);
  });

  Event redacted(String body) {
    final event = message(body, sender: harness.client.userID);
    event.setRedactionEvent(
      Event(
        type: EventTypes.Redaction,
        content: {},
        room: harness.room,
        eventId: '\$r${counter++}:example.org',
        senderId: harness.client.userID!,
        originServerTs: DateTime(2030, 1, 1, 12, 42),
      ),
    );
    return event;
  }

  testWidgets('a deleted message has no menu, no hover and cannot be selected '
      '(REV M-2)', (tester) async {
    final event = redacted('secret words');
    final controller = await openWith(tester, [event], width: 1000);
    expect(find.textContaining('deleted this message'), findsOneWidget);
    await tester.longPress(find.textContaining('deleted this message'));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.textContaining('deleted this message')),
    );
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('message_hover_actions')), findsNothing);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.textContaining('deleted this message'),
          matching: find.byType(MessageFocus),
        ),
        matching: find.byType(CallbackShortcuts),
      ),
      findsNothing,
    );
    controller.selectOnly(event);
    expect(controller.selectedEvents, isEmpty);
    expect(availableMessageActions(messageActionContext(controller, event)), [
      MessageAction.info,
    ]);
    await harness.finish(tester);
  });

  testWidgets('an undecryptable message offers no copy, forward, edit or pin '
      '(SEC L1)', (tester) async {
    final utd = Event(
      type: EventTypes.Encrypted,
      content: {
        'msgtype': MessageTypes.BadEncrypted,
        'body': 'ciphertext',
        'algorithm': 'm.megolm.v1.aes-sha2',
        'can_request_session': true,
      },
      room: harness.room,
      eventId: '\$u${counter++}:example.org',
      senderId: harness.client.userID!,
      originServerTs: DateTime(2030, 1, 1, 12, 41),
      status: EventStatus.synced,
    );
    final controller = await openWith(tester, [utd]);
    final actions = availableMessageActions(
      messageActionContext(controller, utd),
    );
    for (final forbidden in [
      MessageAction.copy,
      MessageAction.forward,
      MessageAction.edit,
      MessageAction.pin,
      MessageAction.unpin,
      MessageAction.saveFile,
    ]) {
      expect(actions, isNot(contains(forbidden)));
    }
    expect(actions, containsAll([MessageAction.reply, MessageAction.info]));
    await harness.finish(tester);
  });

  testWidgets('in a short window at large text the last row is reachable '
      '(REV M-4)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openWith(
      tester,
      [message('mine', sender: harness.client.userID)],
      width: 640,
      height: 360,
    );
    await longPress(tester, 'mine');
    final card = find.byType(GlassMenuCard);
    expect(card, findsOneWidget);
    expect(tester.getRect(card).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(360));
    final scrollable = find.descendant(
      of: card,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Delete for everyone'),
      40,
      scrollable: scrollable,
    );
    final row = tester.getRect(find.text('Delete for everyone'));
    expect(row.bottom, lessThanOrEqualTo(tester.getRect(card).bottom));
    await harness.finish(tester);
  });

  Future<void> tabToMessage(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.findAncestorWidgetOfExactType<MessageFocus>() != null) {
        return;
      }
    }
    fail('Tab never reached a message');
  }

  testWidgets('Tab to a message and Enter opens the menu with the first row '
      'focused (REV M-5)', (tester) async {
    await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ]);
    await tabToMessage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<GlassMenuRow>(), isNotNull);
    await harness.finish(tester);
  });

  for (final (name, key, shift) in [
    ('the context menu key', LogicalKeyboardKey.contextMenu, false),
    ('Shift+F10', LogicalKeyboardKey.f10, true),
  ]) {
    testWidgets('$name opens the menu on a focused message (REV M-5)', (
      tester,
    ) async {
      await openWith(tester, [
        message('hello there', sender: '@bob:example.org'),
      ]);
      await tabToMessage(tester);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await harness.settle(tester, rounds: 3);
      expect(find.byType(GlassMenuCard), findsOneWidget);
      await harness.finish(tester);
    });
  }

  testWidgets('a screen reader gets a named "More options" action (REV M-5)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ]);
    final target = find.ancestor(
      of: find.text('hello there'),
      matching: find.byType(MessageFocus),
    );
    final ids = tester
        .getSemantics(target)
        .getSemanticsData()
        .customSemanticsActionIds!;
    final action = ids
        .map((id) => CustomSemanticsAction.getAction(id)!)
        .singleWhere((action) => action.label == 'More options');
    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      tester.getSemantics(target).id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(action),
    );
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsOneWidget);
    semantics.dispose();
    await harness.finish(tester);
  });

  testWidgets('opening, closing and selecting send nothing (SEC I2)', (
    tester,
  ) async {
    await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ]);
    FakeMatrixApi.calledEndpoints.clear();
    await longPress(tester, 'hello there');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 3);
    await longPress(tester, 'hello there');
    await tester.tap(find.text('Select'));
    await harness.settle(tester, rounds: 3);
    final leaked = sent().where(
      (path) =>
          path.contains('receipt') ||
          path.contains('read_markers') ||
          path.contains('typing') ||
          path.contains('presence'),
    );
    expect(leaked, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the menu is taller at large text and still fits (REV M-4)', (
    tester,
  ) async {
    await openWith(tester, [
      message('mine', sender: harness.client.userID),
    ], height: 1400);
    await longPress(tester, 'mine');
    final normal = tester.getSize(find.byType(GlassMenuCard)).height;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 3);
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await harness.settle(tester, rounds: 3);
    while (tester.takeException() != null) {}
    await longPress(tester, 'mine');
    while (tester.takeException() != null) {}
    final large = tester.getSize(find.byType(GlassMenuCard)).height;
    expect(large, greaterThan(normal));
    await harness.finish(tester);
  });

  testWidgets('hover actions are gone while selecting', (tester) async {
    final controller = await openWith(tester, [
      message('hello there', sender: '@bob:example.org'),
    ], width: 1000);
    controller.selectOnly(controller.timeline!.events.first);
    await harness.settle(tester, rounds: 2);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('hello there')));
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('message_hover_actions')), findsNothing);
    await harness.finish(tester);
  });

  for (final (brightness, suffix) in [
    (Brightness.light, 'light'),
    (Brightness.dark, 'dark'),
  ]) {
    testWidgets('golden $suffix', (tester) async {
      await harness.open(tester, brightness: brightness);
      final controller = controllerOf(tester);
      harness.room.ephemerals.remove('m.typing');
      controller.timeline!.events.insert(0, message('hello there'));
      controller.updateView();
      await harness.settle(tester, rounds: 3);
      await longPress(tester, 'hello there');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_menu_$suffix.png'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await harness.settle(tester, rounds: 2);
      await harness.finish(tester);
    });
  }
}
