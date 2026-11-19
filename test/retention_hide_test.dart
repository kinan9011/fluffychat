// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:odango/utils/retention/retention_policy.dart';

import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  final now = DateTime.utc(2031, 6, 1, 12);
  const policy = RetentionPolicy(Duration(days: 1));

  setUpAll(() async {
    client = await prepareTestClient();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  Event message(String id, Duration age, {String? thread}) => Event(
    type: EventTypes.Message,
    content: {
      'msgtype': 'm.text',
      'body': id,
      if (thread != null)
        'm.relates_to': {'rel_type': 'm.thread', 'event_id': thread},
    },
    room: room,
    eventId: id,
    senderId: '@bob:example.org',
    originServerTs: now.subtract(age),
  );

  List<String> ids(List<Event> events) => events.map((e) => e.eventId).toList();

  test('expired messages are dropped, fresh ones and state stay', () {
    final events = [
      message(r'$new', const Duration(hours: 1)),
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'x'},
        room: room,
        eventId: r'$name',
        senderId: '@bob:example.org',
        originServerTs: now.subtract(const Duration(days: 40)),
      ),
      message(r'$old', const Duration(days: 3)),
    ];
    final visible = events.filterByVisibleInGui(retention: policy, now: now);
    expect(ids(visible), [r'$new', r'$name']);
  });

  test('without a policy everything is shown', () {
    final events = [message(r'$old', const Duration(days: 3))];
    expect(ids(events.filterByVisibleInGui(now: now)), [r'$old']);
  });

  test(
    'hiding is not deleting: the timeline and the database keep them',
    () async {
      final timeline = await room.getTimeline();
      final before = ids(timeline.events);
      expect(before, isNotEmpty);
      final visible = timeline.events.filterByVisibleInGui(
        retention: policy,
        now: DateTime.now(),
      );
      expect(
        visible.where((e) => e.type == EventTypes.Message),
        isEmpty,
        reason: 'the fixture messages are years old',
      );
      expect(ids(timeline.events), before);
      for (final event in timeline.events.where(
        (e) => e.type == EventTypes.Message,
      )) {
        final stored = await room.getEventById(event.eventId);
        expect(stored, isNotNull, reason: event.eventId);
      }
      timeline.cancelSubscriptions();
    },
  );

  test('a jump target is not lost', () {
    final events = [
      message(r'$old', const Duration(days: 3)),
      message(r'$older', const Duration(days: 5)),
    ];
    final visible = events.filterByVisibleInGui(
      retention: policy,
      now: now,
      exceptionEventId: r'$old',
    );
    expect(ids(visible), [r'$old']);
  });

  test('the thread filter and the timer combine', () {
    final events = [
      message(r'$root', const Duration(hours: 2)),
      message(r'$fresh', const Duration(hours: 1), thread: r'$root'),
      message(r'$stale', const Duration(days: 3), thread: r'$root'),
      message(r'$other', const Duration(hours: 1), thread: r'$elsewhere'),
    ];
    final visible = events.filterByVisibleInGui(
      retention: policy,
      now: now,
      threadId: r'$root',
    );
    expect(ids(visible), [r'$root', r'$fresh']);
    final main = events.filterByVisibleInGui(retention: policy, now: now);
    expect(ids(main), [r'$root']);
  });

  test('taking the policy away shows the messages again', () {
    final events = [message(r'$old', const Duration(days: 3))];
    expect(
      ids(events.filterByVisibleInGui(retention: policy, now: now)),
      isEmpty,
    );
    expect(ids(events.filterByVisibleInGui(retention: null, now: now)), [
      r'$old',
    ]);
  });
}
