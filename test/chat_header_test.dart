// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat_header.dart';
import 'package:fluffychat/pages/chat/chat_overflow_menu.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(() async {
    await harness.tearDown();
    await AppSettings.reduceTransparency.setItem(false);
  });

  testWidgets('phone: back circle, title pill and overflow circle', (
    tester,
  ) async {
    await harness.open(tester);
    expect(
      find.descendant(
        of: find.byType(ChatHeader),
        matching: find.byType(BackButton),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat_overflow_button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatHeader),
        matching: find.text(harness.room.getLocalizedDisplayname()),
      ),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets('column layout: no back circle', (tester) async {
    await harness.open(tester, width: 1000);
    expect(
      find.descendant(
        of: find.byType(ChatHeader),
        matching: find.byType(BackButton),
      ),
      findsNothing,
    );
    await harness.finish(tester);
  });

  testWidgets('header does not overflow at 360 px height', (tester) async {
    await harness.open(tester, width: 700, height: 360);
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  testWidgets('overflow menu shows only real actions and Escape closes it', (
    tester,
  ) async {
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 3);
    for (final label in [
      'Search',
      'Change wallpaper',
      'Export chat',
      'Leave chat',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Scheduled messages'), findsOneWidget);
    expect(find.text('Clear history'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 3);
    expect(find.text('Change wallpaper'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('overflow entries are exactly chatOverflowActions', (
    tester,
  ) async {
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 3);
    final room = harness.room;
    final expected = chatOverflowActions(
      muted: room.pushRuleState != PushRuleState.notify,
      canCall: false,
      showDetails: true,
      joined: true,
      left: false,
      canSchedule: room.canSendDefaultMessages,
    );
    expect(expected, contains(ChatOverflowAction.scheduled));
    expect(find.byType(GlassMenuRow), findsNWidgets(expected.length));
    await harness.finish(tester);
  });

  testWidgets('the overflow menu sits right under the button even with a '
      'status bar inset (REV m2)', (tester) async {
    await harness.open(tester);
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.viewPadding = const FakeViewPadding(top: 40);
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 3);
    final button = tester.getRect(
      find.byKey(const Key('chat_overflow_button')),
    );
    expect(
      tester.getRect(find.byType(GlassMenuCard)).top,
      closeTo(button.bottom + 8, 1),
    );
    await harness.finish(tester);
  });

  testWidgets('in a short window the overflow menu scrolls and stays on '
      'screen (REV M-4)', (tester) async {
    await harness.open(tester, width: 700, height: 240);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 3);
    final card = find.byType(GlassMenuCard);
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(240));
    await tester.scrollUntilVisible(
      find.text('Leave chat'),
      40,
      scrollable: find.descendant(of: card, matching: find.byType(Scrollable)),
    );
    expect(
      tester.getRect(find.text('Leave chat')).bottom,
      lessThanOrEqualTo(tester.getRect(card).bottom),
    );
    await harness.finish(tester);
  });

  testWidgets('the header status line is fg on glass, one safe line '
      '(REV M-6, SEC L4)', (tester) async {
    final direct = harness.client.accountData['m.direct'];
    harness.client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: const {},
    );
    addTearDown(() => harness.client.accountData['m.direct'] = direct!);
    final room = harness.room;
    final topic = room.getState(EventTypes.RoomTopic);
    room.setState(
      Event(
        type: EventTypes.RoomTopic,
        stateKey: '',
        content: {'topic': 'plan\n\n\u202Eevil topic'},
        room: room,
        eventId: r'$topic:example.org',
        senderId: '@bob:example.org',
        originServerTs: DateTime(2030),
      ),
    );
    addTearDown(() {
      if (topic != null) room.setState(topic);
    });
    await harness.open(tester);
    final status = tester.widget<Text>(find.text('plan evil topic'));
    expect(status.style?.color, AppTokens.light().fg);
    await harness.finish(tester);
  });

  testWidgets('Leave chat asks first and cancelling keeps the room', (
    tester,
  ) async {
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.text('Leave chat'));
    await harness.settle(tester, rounds: 3);
    expect(find.text('Are you sure?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await harness.settle(tester, rounds: 3);
    expect(harness.room.membership, Membership.join);
    await harness.finish(tester);
  });

  testWidgets('reduce transparency removes the blur from the header', (
    tester,
  ) async {
    await harness.open(tester);
    Finder blur() => find.descendant(
      of: find.byType(ChatHeader),
      matching: find.byType(BackdropFilter),
    );
    expect(blur(), findsWidgets);
    await AppSettings.reduceTransparency.setItem(true);
    await harness.settle(tester, rounds: 2);
    expect(blur(), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('goldens in light and dark', (tester) async {
    for (final (brightness, suffix) in [
      (Brightness.light, 'light'),
      (Brightness.dark, 'dark'),
    ]) {
      await harness.open(tester, brightness: brightness);
      await tester.tap(find.byKey(const Key('chat_overflow_button')));
      await harness.settle(tester, rounds: 3);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/chat_header_$suffix.png'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await harness.settle(tester, rounds: 3);
      await harness.finish(tester);
    }
  });
}
