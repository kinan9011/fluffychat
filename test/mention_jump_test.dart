// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat/mention_jump.dart';

import 'utils/test_client.dart';

const _me = '@me:example.org';

Event _event(
  Room room,
  String id, {
  String sender = '@bob:example.org',
  Map<String, Object?> extra = const {},
  bool redacted = false,
}) {
  final event = Event(
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': 'hi $id', ...extra},
    room: room,
    eventId: id,
    senderId: sender,
    originServerTs: DateTime(2030),
  );
  if (redacted) {
    event.setRedactionEvent(
      Event(
        type: EventTypes.Redaction,
        content: const {},
        room: room,
        eventId: '\$r$id',
        senderId: sender,
        originServerTs: DateTime(2030),
      ),
    );
  }
  return event;
}

Map<String, Object?> _mentions(List<String> ids) => {
  'm.mentions': {'user_ids': ids},
};

void main() {
  late Room room;
  setUpAll(() async {
    room = Room(id: '!r:example.org', client: await prepareTestClient());
  });

  List<String> pending(
    List<Event> newestFirst, {
    String? fullyRead,
    bool Function(Event)? isHighlight,
    String? own = _me,
    int? maxScan,
    MentionJump? jump,
  }) => (jump ?? MentionJump()).pending(
    eventsNewestFirst: newestFirst,
    ownUserId: own,
    fullyReadEventId: fullyRead,
    isHighlight: isHighlight ?? (_) => false,
    maxScan: maxScan ?? 500,
  );

  test('returns unread highlighted events oldest first', () {
    final events = [
      _event(room, r'$3'),
      _event(room, r'$2'),
      _event(room, r'$1'),
    ];
    expect(pending(events, isHighlight: (e) => e.eventId != r'$2'), [
      r'$1',
      r'$3',
    ]);
  });

  test('events at or before the read marker are excluded', () {
    final events = [
      _event(room, r'$3'),
      _event(room, r'$2'),
      _event(room, r'$1'),
    ];
    expect(pending(events, fullyRead: r'$2', isHighlight: (_) => true), [
      r'$3',
    ]);
  });

  test('own events are never mentions', () {
    final events = [_event(room, r'$1', sender: _me)];
    expect(pending(events, isHighlight: (_) => true), isEmpty);
  });

  test('m.mentions user_ids counts even when no push rule matches', () {
    final events = [
      _event(room, r'$1', extra: _mentions([_me])),
    ];
    expect(pending(events), [r'$1']);
  });

  test('a mention of somebody else does not count', () {
    final events = [
      _event(room, r'$1', extra: _mentions(['@other:example.org'])),
    ];
    expect(pending(events), isEmpty);
  });

  test('redacted events are skipped', () {
    final events = [_event(room, r'$1', redacted: true)];
    expect(pending(events, isHighlight: (_) => true), isEmpty);
  });

  test('the scan stops after maxScan events', () {
    final events = [for (var i = 0; i < 501; i++) _event(room, '\$$i')];
    final result = pending(
      events,
      isHighlight: (e) => e.eventId == r'$500' || e.eventId == r'$0',
    );
    expect(result, [r'$0']);
  });

  test('next skips visited ids and walks the list', () {
    final jump = MentionJump();
    final events = [_event(room, r'$2'), _event(room, r'$1')];
    final list = pending(events, isHighlight: (_) => true, jump: jump);
    expect(jump.next(list), r'$1');
    jump.visit(r'$1');
    expect(pending(events, isHighlight: (_) => true, jump: jump), [r'$2']);
    jump.visit(r'$2');
    expect(jump.next(list), isNull);
  });

  test('reset forgets visited ids', () {
    final jump = MentionJump()..visit(r'$1');
    jump.reset();
    expect(
      pending([_event(room, r'$1')], isHighlight: (_) => true, jump: jump),
      [r'$1'],
    );
  });

  test('no own user id means no mentions', () {
    expect(
      pending([_event(room, r'$1')], own: null, isHighlight: (_) => true),
      isEmpty,
    );
  });

  group('nextLoading', () {
    List<Event> events() => [_event(room, r'$m')];

    test('a loaded mention needs no history', () async {
      var loads = 0;
      final jump = MentionJump();
      final id = await jump.nextLoading(
        pending: () => pending(events(), isHighlight: (_) => true, jump: jump),
        canLoadMore: () => true,
        loadMore: () async => loads++,
      );
      expect(id, r'$m');
      expect(loads, 0);
    });

    test('older history is loaded until a mention shows up', () async {
      var loads = 0;
      final jump = MentionJump();
      final id = await jump.nextLoading(
        pending: () => loads < 3
            ? []
            : pending(events(), isHighlight: (_) => true, jump: jump),
        canLoadMore: () => true,
        loadMore: () async => loads++,
      );
      expect(id, r'$m');
      expect(loads, 3);
    });

    test('it gives up after five rounds', () async {
      var loads = 0;
      final id = await MentionJump().nextLoading(
        pending: () => [],
        canLoadMore: () => true,
        loadMore: () async => loads++,
      );
      expect(id, isNull);
      expect(loads, 5);
    });

    test('it stops when there is nothing more to load', () async {
      var loads = 0;
      final id = await MentionJump().nextLoading(
        pending: () => [],
        canLoadMore: () => false,
        loadMore: () async => loads++,
      );
      expect(id, isNull);
      expect(loads, 0);
    });

    test('a failing load surfaces to the caller', () async {
      expect(
        MentionJump().nextLoading(
          pending: () => [],
          canLoadMore: () => true,
          loadMore: () async => throw Exception('offline'),
        ),
        throwsException,
      );
    });
  });

  group('the count and the budget (REV M-3)', () {
    Future<String?> search(MentionJump jump, {required bool more}) =>
        jump.nextLoading(
          pending: () => [],
          canLoadMore: () => more,
          loadMore: () async {},
        );

    test('before a search the server count shows', () {
      final jump = MentionJump();
      expect(jump.countFor(localPending: 0, serverCount: 3), 3);
      expect(jump.countFor(localPending: 5, serverCount: 3), 5);
      jump.visit('a');
      expect(jump.countFor(localPending: 0, serverCount: 3), 2);
    });

    test(
      'a search that reached the end of history drops the server count',
      () async {
        final jump = MentionJump();
        await search(jump, more: false);
        expect(jump.exhausted, isTrue);
        expect(jump.countFor(localPending: 0, serverCount: 3), 0);
        expect(jump.countFor(localPending: 2, serverCount: 3), 2);
      },
    );

    test('five empty rounds with more history keep the count', () async {
      final jump = MentionJump();
      await search(jump, more: true);
      expect(jump.exhausted, isFalse);
      expect(jump.countFor(localPending: 0, serverCount: 3), 3);
    });

    test('twenty rounds in total are the budget', () async {
      var loads = 0;
      final jump = MentionJump();
      for (var tap = 0; tap < 6; tap++) {
        await jump.nextLoading(
          pending: () => [],
          canLoadMore: () => true,
          loadMore: () async => loads++,
        );
      }
      expect(loads, 20);
      expect(jump.exhausted, isTrue);
    });

    test('a changed server count searches again', () async {
      final jump = MentionJump();
      await search(jump, more: false);
      jump.rearm();
      expect(jump.exhausted, isFalse);
      expect(jump.countFor(localPending: 0, serverCount: 1), 1);
    });

    test('a new unread state forgets visits and the search', () async {
      final jump = MentionJump();
      jump.visit('a');
      await search(jump, more: false);
      jump.reset();
      expect(jump.visitedCount, 0);
      expect(jump.exhausted, isFalse);
    });

    test('every loaded round widens the scan', () async {
      final events = [for (var i = 0; i < 600; i++) _event(room, '\$e$i')];
      final jump = MentionJump();
      bool oldest(Event e) => e.eventId == r'$e599';
      expect(
        pending(events, isHighlight: oldest, maxScan: 500, jump: jump),
        isEmpty,
      );
      await jump.nextLoading(
        pending: () => [],
        canLoadMore: () => true,
        loadMore: () async {},
        maxRounds: 1,
        scanPerRound: 100,
      );
      expect(pending(events, isHighlight: oldest, maxScan: 500, jump: jump), [
        r'$e599',
      ]);
    });

    test('visiting and resetting change the revision', () {
      final jump = MentionJump();
      final start = jump.revision;
      jump.visit('a');
      final visited = jump.revision;
      jump.reset();
      expect(visited, greaterThan(start));
      expect(jump.revision, greaterThan(visited));
    });
  });
}
