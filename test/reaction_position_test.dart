// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/reaction_bar.dart';
import 'package:fluffychat/pages/chat/events/reaction_pills.dart';
import 'package:fluffychat/utils/chat/bubble_shape.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/reaction_fixtures.dart';

const _longText =
    'This is a long message that has to wrap over several lines inside the '
    'bubble so that the bubble is as wide as the timeline allows it to be.';

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

  for (final size in [const Size(360, 640), const Size(1200, 900)]) {
    for (final reduceMotion in [true, false]) {
      group('${size.width.toInt()}x${size.height.toInt()}'
          '${reduceMotion ? '' : ' with motion'}', () {
        for (final (name, sender, text) in [
          ('incoming short', otherSender, 'Ok'),
          ('outgoing short', ownSender, 'Ok'),
          ('incoming long', otherSender, _longText),
          ('outgoing long', ownSender, _longText),
        ]) {
          testWidgets('$name message: the reaction sits under its bubble', (
            tester,
          ) async {
            await harness.open(
              tester,
              width: size.width,
              height: size.height,
              reduceMotion: reduceMotion,
            );
            final message = fixtureMessage(
              harness.room,
              sender: sender,
              text: text,
            );
            await showMessages(
              tester,
              harness,
              [message],
              [fixtureReaction(harness.room, message, '👍')],
            );
            if (!reduceMotion) {
              await tester.pump(const Duration(milliseconds: 600));
            }
            expectChipAttached(
              bubbleRect(tester, text),
              chipRect(tester, '👍'),
              atStart: sender == otherSender,
              direction: TextDirection.ltr,
              reason: name,
            );
            await harness.finish(tester);
          });
        }
      });
    }
  }

  testWidgets('five reactions wrap inside the bubble width, not the screen', (
    tester,
  ) async {
    await harness.open(tester);
    final message = fixtureMessage(
      harness.room,
      sender: otherSender,
      text: 'Ok',
    );
    const keys = ['👍', '❤️', '😂', '🎉', '🙏'];
    await showMessages(
      tester,
      harness,
      [message],
      [for (final key in keys) fixtureReaction(harness.room, message, key)],
    );
    final bubble = bubbleRect(tester, 'Ok');
    final first = chipRect(tester, keys.first);
    expectChipAttached(
      bubble,
      first,
      atStart: true,
      direction: TextDirection.ltr,
    );
    final pills = tester.getRect(find.byType(ReactionPills));
    expect(pills.left, lessThanOrEqualTo(bubble.left + 1));
    expect(pills.right, lessThanOrEqualTo(400 - 8 + 1));
    expect(
      pills.width,
      lessThanOrEqualTo(bubbleMaxWidth(400) + 1),
      reason: 'the chips wrap at the widest a bubble can be',
    );
    await harness.finish(tester);
  });

  for (final (name, sender) in [
    ('incoming', otherSender),
    ('outgoing', ownSender),
  ]) {
    testWidgets('$name: the +N label of hidden keys sits at the bubble side', (
      tester,
    ) async {
      await harness.open(tester);
      final message = fixtureMessage(harness.room, sender: sender, text: 'Ok');
      await showMessages(
        tester,
        harness,
        [message],
        [
          for (var i = 0; i < 30; i++)
            fixtureReaction(harness.room, message, 'k$i'),
        ],
      );
      expect(find.text('+6'), findsOneWidget);
      expectMoreAtSide(
        tester.getRect(find.byType(ReactionPills)),
        moreRect(tester),
        reason: name,
      );
      await harness.finish(tester);
    });
  }

  testWidgets('a hostile 200 character key is dropped', (tester) async {
    await harness.open(tester);
    final message = fixtureMessage(harness.room, sender: ownSender);
    await showMessages(
      tester,
      harness,
      [message],
      [fixtureReaction(harness.room, message, 'x' * 200)],
    );
    expect(find.textContaining('xxxxx'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a 120 character key is cut to a short chip at the bubble', (
    tester,
  ) async {
    await harness.open(tester);
    final message = fixtureMessage(harness.room, sender: ownSender);
    final key = 'w' * 120;
    await showMessages(
      tester,
      harness,
      [message],
      [fixtureReaction(harness.room, message, key)],
    );
    final chip = chipRect(tester, key);
    expect(chip.width, lessThan(160));
    expectChipAttached(
      bubbleRect(tester, 'Hello there'),
      chip,
      atStart: false,
      direction: TextDirection.ltr,
    );
    await harness.finish(tester);
  });

  testWidgets('a reaction that is still sending sits in the same place', (
    tester,
  ) async {
    await harness.open(tester);
    final message = fixtureMessage(harness.room, sender: otherSender);
    await showMessages(
      tester,
      harness,
      [message],
      [
        fixtureReaction(
          harness.room,
          message,
          '👍',
          sender: ownSender,
          status: EventStatus.sending,
        ),
      ],
    );
    expectChipAttached(
      bubbleRect(tester, 'Hello there'),
      chipRect(tester, '👍'),
      atStart: true,
      direction: TextDirection.ltr,
    );
    await harness.finish(tester);
  });

  testWidgets('a reaction event never shows up as a row of its own', (
    tester,
  ) async {
    await harness.open(tester);
    final message = fixtureMessage(harness.room, sender: otherSender);
    final reaction = fixtureReaction(harness.room, message, '👍');
    await showMessages(tester, harness, [message, reaction], [reaction]);
    expect(find.byType(ReactionPills), findsOneWidget);
    expect(find.textContaining('reacted'), findsNothing);
    await harness.finish(tester);
  });

  group('other ways a message and its reaction can look', () {
    testWidgets('a reply keeps the chip at the bubble', (tester) async {
      await harness.open(tester);
      final parent = fixtureMessage(
        harness.room,
        sender: ownSender,
        text: 'the question',
      );
      final reply = fixtureMessage(
        harness.room,
        sender: otherSender,
        content: {
          'msgtype': MessageTypes.Text,
          'body': 'the answer',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': parent.eventId},
          },
        },
      );
      await showMessages(
        tester,
        harness,
        [parent, reply],
        [fixtureReaction(harness.room, reply, '👍')],
      );
      expectChipAttached(
        bubbleRectOf(tester, reply),
        chipRect(tester, '👍'),
        atStart: true,
        direction: TextDirection.ltr,
      );
      await harness.finish(tester);
    });

    testWidgets('an image without caption keeps the chip at the picture', (
      tester,
    ) async {
      await harness.open(tester);
      final image = fixtureMessage(
        harness.room,
        sender: otherSender,
        content: {
          'msgtype': MessageTypes.Image,
          'body': 'photo.png',
          'url': 'mxc://example.org/photo',
          'info': {'w': 300, 'h': 200, 'mimetype': 'image/png'},
        },
      );
      await showMessages(
        tester,
        harness,
        [image],
        [fixtureReaction(harness.room, image, '👍')],
      );
      expectChipAttached(
        bubbleRectOf(tester, image),
        chipRect(tester, '👍'),
        atStart: true,
        direction: TextDirection.ltr,
      );
      await harness.finish(tester);
    });

    testWidgets('in selection mode the chip stays at the bubble', (
      tester,
    ) async {
      await harness.open(tester);
      final message = fixtureMessage(harness.room, sender: otherSender);
      await showMessages(
        tester,
        harness,
        [message],
        [fixtureReaction(harness.room, message, '👍')],
      );
      chatOf(tester).selectedEvents.add(message);
      chatOf(tester).updateView();
      await harness.settle(tester, rounds: 2);
      expectChipAttached(
        bubbleRectOf(tester, message),
        chipRect(tester, '👍'),
        atStart: true,
        direction: TextDirection.ltr,
      );
      await harness.finish(tester);
    });

    testWidgets('hovering a message on the desktop does not move the chip', (
      tester,
    ) async {
      await harness.open(tester, width: 1200, height: 900);
      final message = fixtureMessage(harness.room, sender: ownSender);
      await showMessages(
        tester,
        harness,
        [message],
        [fixtureReaction(harness.room, message, '👍')],
      );
      final before = chipRect(tester, '👍');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Hello there')));
      await harness.settle(tester, rounds: 2);
      expect(find.byKey(const Key('message_hover_actions')), findsOneWidget);
      expect(chipRect(tester, '👍'), before);
      await harness.finish(tester);
    });

    testWidgets(
      'reacting from the long press bar puts the chip at the bubble',
      (tester) async {
        await harness.open(tester);
        final message = fixtureMessage(harness.room, sender: otherSender);
        await showMessages(tester, harness, [message], []);
        await tester.longPress(find.text('Hello there'));
        await harness.settle(tester, rounds: 2);
        expect(find.byType(ReactionBar), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(ReactionBar),
            matching: find.text('👍'),
          ),
        );
        await harness.settle(tester, rounds: 3);
        expect(find.byType(ReactionBar), findsNothing);
        final controller = chatOf(tester);
        final sent = controller.timeline!.events
            .where((event) => event.type == EventTypes.Reaction)
            .toList();
        for (final reaction in sent) {
          controller.timeline!.addAggregatedEvent(reaction);
        }
        controller.updateView();
        await harness.settle(tester, rounds: 2);
        expect(sent, isNotEmpty, reason: 'the local echo of the reaction');
        expectChipAttached(
          bubbleRectOf(tester, message),
          chipRect(tester, '👍'),
          atStart: true,
          direction: TextDirection.ltr,
        );
        await harness.finish(tester);
      },
    );
  });

  for (final (name, sender, atStart) in [
    ('incoming', otherSender, true),
    ('outgoing', ownSender, false),
  ]) {
    testWidgets('$name: a second line of reactions lines up with the first', (
      tester,
    ) async {
      await harness.open(tester, width: 360, height: 640);
      final message = fixtureMessage(harness.room, sender: sender, text: 'Ok');
      const keys = ['👍', '❤️', '😂', '🎉', '🙏', '🔥', '👏', '😮', '😢'];
      await showMessages(
        tester,
        harness,
        [message],
        [for (final key in keys) fixtureReaction(harness.room, message, key)],
      );
      final chips = [for (final key in keys) chipRect(tester, key)];
      final tops = {for (final chip in chips) chip.top.round()};
      expect(tops.length, greaterThan(1), reason: 'the chips wrap');
      final lastLine = chips.where((chip) => chip.top.round() == tops.last);
      final firstLine = chips.where((chip) => chip.top.round() == tops.first);
      double edge(Iterable<Rect> line) => atStart
          ? line.map((chip) => chip.left).reduce((a, b) => a < b ? a : b)
          : line.map((chip) => chip.right).reduce((a, b) => a > b ? a : b);
      expect(edge(lastLine), closeTo(edge(firstLine), 1));
      expect(
        tester.getSize(find.byType(ReactionPills)).width,
        lessThanOrEqualTo(bubbleMaxWidth(360) + 1),
        reason: 'the lines break at the widest a bubble can be',
      );
      await harness.finish(tester);
    });
  }
}
