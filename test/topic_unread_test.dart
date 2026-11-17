// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/topics/topic_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  final receipt = DateTime.utc(2026, 11, 17, 12);
  const me = '@test:fakeServer.notExisting';

  setUpAll(() async {
    client = await prepareTestClient();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  Event event(
    String id,
    Duration after, {
    String sender = '@bob:example.org',
    Map<String, Object?> extra = const {},
  }) => Event(
    type: EventTypes.Message,
    content: {'msgtype': 'm.text', 'body': id, ...extra},
    room: room,
    eventId: id,
    senderId: sender,
    originServerTs: receipt.add(after),
  );

  ({int count, bool mention}) compute(
    List<Event> events, {
    bool read = false,
    DateTime? latest,
    String? latestSender,
    bool Function(Event)? highlight,
  }) => TopicUnread.compute(
    threadEvents: events,
    ownReceiptTimestamp: receipt,
    ownUserId: me,
    isHighlight: highlight ?? (_) => false,
    roomIsRead: read,
    latestActivity: latest,
    latestSenderId: latestSender,
  );

  test('a receipt newer than everything leaves nothing unread', () {
    final result = compute([
      event(r'$a', const Duration(minutes: -5)),
      event(r'$b', const Duration(minutes: -1)),
    ]);
    expect(result, (count: 0, mention: false));
  });

  test('messages of other people after the receipt are counted', () {
    final result = compute([
      event(r'$a', const Duration(minutes: 3)),
      event(r'$b', const Duration(minutes: 2)),
      event(r'$c', const Duration(minutes: 1)),
      event(r'$old', const Duration(minutes: -1)),
    ]);
    expect(result.count, 3);
  });

  test('own messages are never unread', () {
    final result = compute([
      event(r'$a', const Duration(minutes: 3), sender: me),
      event(r'$b', const Duration(minutes: 2)),
    ]);
    expect(result.count, 1);
  });

  test('the count stops at 99', () {
    final events = [
      for (var i = 0; i < 150; i++) event('\$e$i', Duration(minutes: i + 1)),
    ];
    expect(compute(events).count, 99);
  });

  test('nothing loaded but a newer last message counts as one', () {
    final result = compute(
      const [],
      latest: receipt.add(const Duration(hours: 1)),
      latestSender: '@bob:example.org',
    );
    expect(result.count, 1);
    expect(
      compute(
        const [],
        latest: receipt.add(const Duration(hours: 1)),
        latestSender: me,
      ).count,
      0,
    );
    expect(
      compute(
        const [],
        latest: receipt.subtract(const Duration(hours: 1)),
        latestSender: '@bob:example.org',
      ).count,
      0,
    );
  });

  test(
    'no receipt in a read room is no badge, in an unread room all count',
    () {
      final events = [event(r'$a', const Duration(minutes: 1))];
      ({int count, bool mention}) noReceipt({required bool read}) =>
          TopicUnread.compute(
            threadEvents: events,
            ownReceiptTimestamp: null,
            ownUserId: me,
            isHighlight: (_) => false,
            roomIsRead: read,
          );
      expect(noReceipt(read: true).count, 0);
      expect(noReceipt(read: false).count, 1);
    },
  );

  test('a mention comes from the push rules or from m.mentions', () {
    final plain = event(r'$a', const Duration(minutes: 1));
    expect(compute([plain]).mention, isFalse);
    expect(compute([plain], highlight: (_) => true).mention, isTrue);
    final mentioned = event(
      r'$m',
      const Duration(minutes: 1),
      extra: {
        'm.mentions': {
          'user_ids': [me],
        },
      },
    );
    expect(compute([mentioned]).mention, isTrue);
    final other = event(
      r'$o',
      const Duration(minutes: 1),
      extra: {
        'm.mentions': {
          'user_ids': ['@carol:example.org'],
        },
      },
    );
    expect(compute([other]).mention, isFalse);
  });

  test('a mention that was already read does not count', () {
    final read = event(
      r'$m',
      const Duration(minutes: -1),
      extra: {
        'm.mentions': {
          'user_ids': [me],
        },
      },
    );
    expect(compute([read], highlight: (_) => true).mention, isFalse);
  });
}
