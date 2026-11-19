// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';

import 'chat_page_harness.dart';

const otherSender = '@bob:example.org';
const ownSender = '@test:fakeServer.notExisting';

var _counter = 0;

Event fixtureMessage(
  Room room, {
  required String sender,
  String text = 'Hello there',
  Map<String, Object?>? content,
  DateTime? at,
}) => Event(
  type: EventTypes.Message,
  content: content ?? {'msgtype': MessageTypes.Text, 'body': text},
  room: room,
  eventId: '\$r${_counter++}:example.org',
  senderId: sender,
  originServerTs: at ?? DateTime.now(),
);

Event fixtureReaction(
  Room room,
  Event target,
  String key, {
  String sender = otherSender,
  EventStatus status = EventStatus.synced,
}) => Event(
  type: EventTypes.Reaction,
  content: {
    'm.relates_to': {
      'rel_type': RelationshipTypes.reaction,
      'event_id': target.eventId,
      'key': key,
    },
  },
  room: room,
  eventId: '\$a${_counter++}:example.org',
  senderId: sender,
  originServerTs: DateTime.now(),
  status: status,
);

ChatController chatOf(WidgetTester tester) =>
    tester.state<ChatController>(find.byType(ChatPageWithRoom));

/// Puts [messages] at the bottom of the open chat and their [reactions] under
/// them, like a sync would.
Future<void> showMessages(
  WidgetTester tester,
  ChatPageHarness harness,
  List<Event> messages,
  List<Event> reactions,
) async {
  final controller = chatOf(tester);
  controller.timeline!.events.insertAll(0, messages);
  for (final reaction in reactions) {
    controller.timeline!.addAggregatedEvent(reaction);
  }
  controller.updateView();
  await harness.settle(tester, rounds: 3);
}

Rect bubbleRect(WidgetTester tester, String text) => tester.getRect(
  find
      .ancestor(of: find.text(text), matching: find.byType(MessageBubble))
      .first,
);

Rect bubbleRectOf(WidgetTester tester, Event event) => tester.getRect(
  find
      .descendant(
        of: find.byKey(ValueKey(event.eventId)),
        matching: find.byType(MessageBubble),
      )
      .first,
);

Rect chipRect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey('reaction_chip_$key')));

Rect moreRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('reaction_more')));

/// The chip sits directly under the bubble, overlapping its bottom edge by
/// [overlap] px, at the bubble's own side ([atStart]: the start edge, else
/// the end edge), whatever the reading direction.
void expectChipAttached(
  Rect bubble,
  Rect chip, {
  required bool atStart,
  required TextDirection direction,
  double overlap = 4,
  String? reason,
}) {
  expect(
    chip.top,
    inInclusiveRange(bubble.bottom - overlap - 1, bubble.bottom - overlap + 1),
    reason:
        '$reason: chip $chip must overlap the bottom of $bubble by $overlap',
  );
  final physicalLeft = atStart == (direction == TextDirection.ltr);
  final gap = physicalLeft
      ? chip.left - bubble.left
      : bubble.right - chip.right;
  expect(
    gap,
    inInclusiveRange(-1, 12),
    reason:
        '$reason: chip $chip must sit at the '
        '${physicalLeft ? 'left' : 'right'} edge of $bubble',
  );
}

/// One incoming and one outgoing message with reactions, for the goldens.
Future<void> showGoldenConversation(
  WidgetTester tester,
  ChatPageHarness harness,
) async {
  final now = DateTime.now();
  final noon = DateTime(now.year, now.month, now.day, 12, 40);
  final incoming = fixtureMessage(
    harness.room,
    sender: otherSender,
    text: 'Agreed. Pushing it to the beta channel tonight.',
    at: noon,
  );
  final outgoing = fixtureMessage(
    harness.room,
    sender: ownSender,
    text: 'Great, thanks!',
    at: noon,
  );
  await showMessages(
    tester,
    harness,
    [incoming, outgoing],
    [
      fixtureReaction(harness.room, incoming, '👍'),
      fixtureReaction(harness.room, incoming, '❤️', sender: ownSender),
      fixtureReaction(harness.room, incoming, '🎉'),
      fixtureReaction(
        harness.room,
        incoming,
        '🎉',
        sender: '@carol:example.org',
      ),
      fixtureReaction(harness.room, outgoing, '🙏'),
    ],
  );
}

/// The +N label of hidden keys is as small as its text and flows with the
/// chips on the bubble's side: not stretched over the row, not centred.
void expectMoreAtSide(Rect pills, Rect more, {String? reason}) {
  expect(more.width, lessThan(64), reason: '$reason: $more is not a full row');
  expect(more.left, greaterThanOrEqualTo(pills.left - 1), reason: reason);
  expect(more.right, lessThanOrEqualTo(pills.right + 1), reason: reason);
  expect(
    (more.center.dx - pills.center.dx).abs(),
    greaterThan(pills.width / 4),
    reason: '$reason: $more must not sit in the middle of $pills',
  );
}
