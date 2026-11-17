// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:collection';

import 'package:fluffychat/utils/scheduling/scheduled_queue.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

class _MemoryDatabase implements DatabaseApi {
  Map<String, Object?>? document;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {
    document = Map.of(object);
  }

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async =>
      document == null ? null : (content: document!, savedAt: DateTime(2025));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const roomId = '!a:example.org';
final base = DateTime(2025, 11, 13, 10);

ScheduledEntry entry(
  String id, {
  DateTime? sendAt,
  String? untilOnline,
  ScheduledState state = ScheduledState.pending,
  ScheduledMode mode = ScheduledMode.device,
  String body = 'hello',
}) => ScheduledEntry(
  id: id,
  roomId: roomId,
  mode: mode,
  sendAt: untilOnline == null ? sendAt ?? base : null,
  untilOnline: untilOnline,
  createdAt: base.subtract(const Duration(hours: 1)),
  delayId: mode == ScheduledMode.server ? 'delay-$id' : null,
  state: state,
  content: {'msgtype': 'm.text', 'body': body},
);

class _Harness {
  _Harness() {
    store = ScheduledStore.forTesting(() => database, now: () => now);
    queue = ScheduledQueue(
      store,
      send: (room, content) async {
        sent.add((room, content));
        stateAtSend.add(store.entries().map((e) => e.state).toList());
        if (gates.isNotEmpty) await gates.removeFirst().future;
        await sendGate?.future;
        if (failSend) throw StateError('SENTINEL-SEND-FAILURE');
      },
      now: () => now,
      onlineUsers: online.stream,
      isOnline: (user) async {
        await onlineGate?.future;
        return onlineNow.contains(user);
      },
    );
  }

  final database = _MemoryDatabase();
  late final ScheduledStore store;
  late final ScheduledQueue queue;
  final sent = <(String, Map<String, Object?>)>[];
  final stateAtSend = <List<ScheduledState>>[];
  final online = StreamController<String>.broadcast();
  final onlineNow = <String>{};
  Completer<void>? sendGate;
  Completer<void>? onlineGate;
  final gates = Queue<Completer<void>>();
  bool failSend = false;
  DateTime now = base;

  ScheduledEntry only() => store.entries().single;
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() {
    h.queue.stop();
    h.online.close();
  });

  group('device entries', () {
    test('an entry due now is sent once and removed', () async {
      await h.store.put(entry('entry-0001'));
      await h.queue.start();
      expect(h.sent, hasLength(1));
      expect(h.sent.single.$1, roomId);
      expect(h.sent.single.$2['body'], 'hello');
      expect(h.store.entries(), isEmpty);
      await h.queue.evaluate();
      expect(h.sent, hasLength(1));
    });

    test('an entry that is not due stays untouched', () async {
      await h.store.put(
        entry('entry-0001', sendAt: base.add(const Duration(seconds: 1))),
      );
      await h.queue.start();
      expect(h.sent, isEmpty);
      expect(h.only().state, ScheduledState.pending);
    });

    test('the entry is stored as sending before the message leaves', () async {
      await h.store.put(entry('entry-0001'));
      await h.queue.start();
      expect(h.stateAtSend.single, [ScheduledState.sending]);
    });

    test('ten minutes late is still sent, one second more is not', () async {
      await h.store.put(entry('entry-0001'));
      h.now = base.add(const Duration(minutes: 10));
      await h.queue.start();
      expect(h.sent, hasLength(1));

      await h.store.put(entry('entry-0002'));
      h.now = base.add(const Duration(minutes: 10, seconds: 1));
      await h.queue.evaluate();
      expect(h.sent, hasLength(1));
      expect(h.only().state, ScheduledState.failed);
    });

    test(
      'a clock that jumps two hours fails the entry, never sends it',
      () async {
        await h.store.put(
          entry('entry-0001', sendAt: base.add(const Duration(minutes: 5))),
        );
        await h.queue.start();
        h.now = base.add(const Duration(hours: 2));
        await h.queue.evaluate();
        expect(h.sent, isEmpty);
        expect(h.only().state, ScheduledState.failed);
      },
    );

    test(
      'an entry that was sending when the app died is not sent again',
      () async {
        await h.store.put(entry('entry-0001', state: ScheduledState.sending));
        final restarted = ScheduledStore.forTesting(
          () => h.database,
          now: () => h.now,
        );
        final queue = ScheduledQueue(
          restarted,
          send: (room, content) async => h.sent.add((room, content)),
          now: () => h.now,
        );
        await queue.start();
        expect(h.sent, isEmpty);
        expect(restarted.entries().single.state, ScheduledState.failed);
        queue.stop();
      },
    );

    test('a failing send marks the entry failed and logs no text', () async {
      Logs().outputEvents.clear();
      h.failSend = true;
      await h.store.put(entry('entry-0001', body: 'SENTINEL-PLAIN-9'));
      await h.queue.start();
      expect(h.only().state, ScheduledState.failed);
      for (final event in Logs().outputEvents) {
        expect(event.title, isNot(contains('SENTINEL')));
        expect('${event.exception}', isNot(contains('SENTINEL')));
      }
    });

    test('a failed entry can be sent now', () async {
      await h.store.put(entry('entry-0001', state: ScheduledState.failed));
      await h.queue.start();
      expect(h.sent, isEmpty);
      await h.queue.sendNow('entry-0001');
      expect(h.sent, hasLength(1));
      expect(h.store.entries(), isEmpty);
    });

    test('send now while the timer sends the same entry sends once', () async {
      h.sendGate = Completer<void>();
      await h.store.put(entry('entry-0001'));
      final started = h.queue.start();
      await pumpEventQueue();
      final manual = h.queue.sendNow('entry-0001');
      await pumpEventQueue();
      h.sendGate!.complete();
      await Future.wait([started, manual]);
      expect(h.sent, hasLength(1));
    });

    test('server entries are not this queue business', () async {
      await h.store.put(entry('entry-0001', mode: ScheduledMode.server));
      await h.queue.start();
      expect(h.sent, isEmpty);
    });
  });

  group('a round never works on a stale copy', () {
    const bob = '@bob:example.org';

    Future<Completer<void>> startWithGatedFirstSend(
      List<ScheduledEntry> entries,
    ) async {
      final gate = Completer<void>();
      h.gates.add(gate);
      for (final e in entries) {
        await h.store.put(e);
      }
      unawaited(h.queue.start());
      await pumpEventQueue();
      expect(h.sent, hasLength(1), reason: 'the first send is in flight');
      return gate;
    }

    final first = entry(
      'entry-0001',
      sendAt: base.subtract(const Duration(minutes: 1)),
    );

    test('a message deleted while another one is sent is never sent', () async {
      final gate = await startWithGatedFirstSend([first, entry('entry-0002')]);
      await h.store.remove('entry-0002');
      gate.complete();
      await h.queue.evaluate();
      expect(h.sent, hasLength(1));
      expect(h.store.entries(), isEmpty);
    });

    test('a message moved to tomorrow meanwhile is not sent now', () async {
      final gate = await startWithGatedFirstSend([first, entry('entry-0002')]);
      final tomorrow = base.add(const Duration(days: 1));
      await h.store.put(entry('entry-0002', sendAt: tomorrow));
      gate.complete();
      await h.queue.evaluate();
      expect(h.sent, hasLength(1));
      expect(h.store.entries().single.sendAt, tomorrow);
      expect(h.store.entries().single.state, ScheduledState.pending);
    });

    test('a message sent by send now meanwhile is not sent again', () async {
      final gate = await startWithGatedFirstSend([first, entry('entry-0002')]);
      await h.queue.sendNow('entry-0002');
      expect(h.sent, hasLength(2));
      gate.complete();
      await h.queue.evaluate();
      expect(h.sent, hasLength(2));
      expect(h.store.entries(), isEmpty);
    });

    test('a presence event and a round send the same entry once', () async {
      await h.store.put(entry('entry-bob01', untilOnline: bob));
      h.onlineNow.add(bob);
      h.onlineGate = Completer<void>();
      unawaited(h.queue.start());
      await pumpEventQueue();
      h.online.add(bob);
      await pumpEventQueue();
      expect(h.sent, hasLength(1));
      h.onlineGate!.complete();
      await h.queue.evaluate();
      expect(h.sent, hasLength(1));
    });

    test('a message deleted before it is marked late stays deleted', () async {
      await h.store.put(entry('entry-bob01', untilOnline: bob));
      await h.store.put(
        entry('entry-0002', sendAt: base.subtract(const Duration(minutes: 11))),
      );
      h.onlineGate = Completer<void>();
      unawaited(h.queue.start());
      await pumpEventQueue();
      await h.store.remove('entry-0002');
      h.onlineGate!.complete();
      await h.queue.evaluate();
      expect(h.store.entries().map((e) => e.id), ['entry-bob01']);
    });

    test('a message deleted while it is sent is not brought back by a '
        'failing send', () async {
      h.failSend = true;
      h.sendGate = Completer<void>();
      await h.store.put(entry('entry-0001'));
      final started = h.queue.start();
      await pumpEventQueue();
      await h.store.remove('entry-0001');
      h.sendGate!.complete();
      await started;
      expect(h.store.entries(), isEmpty);
    });

    test('a message moved to tomorrow meanwhile is not marked late', () async {
      await h.store.put(entry('entry-bob01', untilOnline: bob));
      await h.store.put(
        entry('entry-0002', sendAt: base.subtract(const Duration(minutes: 11))),
      );
      h.onlineGate = Completer<void>();
      unawaited(h.queue.start());
      await pumpEventQueue();
      final tomorrow = base.add(const Duration(days: 1));
      await h.store.put(entry('entry-0002', sendAt: tomorrow));
      h.onlineGate!.complete();
      await h.queue.evaluate();
      final moved = h.store.entries().firstWhere((e) => e.id == 'entry-0002');
      expect(moved.state, ScheduledState.pending);
      expect(moved.sendAt, tomorrow);
    });

    test('a presence lookup that ends after stop sends nothing', () async {
      await h.store.put(entry('entry-bob01', untilOnline: bob));
      h.onlineNow.add(bob);
      h.onlineGate = Completer<void>();
      unawaited(h.queue.start());
      await pumpEventQueue();
      h.queue.stop();
      h.onlineGate!.complete();
      await pumpEventQueue();
      expect(h.sent, isEmpty);
      expect(h.only().state, ScheduledState.pending);
    });

    test(
      'a failed entry is not sent by the round or a presence event',
      () async {
        await h.store.put(
          entry('entry-bob01', untilOnline: bob, state: ScheduledState.failed),
        );
        await h.queue.start();
        h.online.add(bob);
        await pumpEventQueue();
        expect(h.sent, isEmpty);
      },
    );
  });

  group('failure reasons', () {
    test('ten minutes and a second late says late', () async {
      await h.store.put(entry('entry-0001'));
      h.now = base.add(const Duration(minutes: 10, seconds: 1));
      await h.queue.start();
      expect(h.only().reason, ScheduledFailure.late);
    });

    test('a send that throws says the send failed', () async {
      h.failSend = true;
      await h.store.put(entry('entry-0001'));
      await h.queue.start();
      expect(h.only().reason, ScheduledFailure.sendFailed);
    });

    test('a when-online wait past 30 days says expired', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      h.now = base.add(const Duration(days: 31));
      await h.queue.start();
      expect(h.only().reason, ScheduledFailure.expired);
    });

    test('a room that is gone says the room is unavailable', () async {
      final client = await prepareTestClient(clientName: 'queue-reason');
      await client.database.cacheCustomObject(ScheduledStore.documentKey, {});
      final store = ScheduledStore.forTesting(
        () => client.database,
        now: () => h.now,
      );
      final queue = ScheduledQueue.forClient(client, store, now: () => h.now);
      await store.put(entry('entry-0001'));
      await queue.start();
      expect(store.entries().single.reason, ScheduledFailure.roomUnavailable);
      queue.stop();
    });
  });

  group('when online', () {
    test('a presence event cannot send a wait of more than 30 days', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      await h.queue.start();
      h.now = base.add(const Duration(days: 31));
      h.online.add('@bob:example.org');
      await pumpEventQueue();
      expect(h.sent, isEmpty);
      expect(h.only().state, ScheduledState.failed);
      expect(h.only().reason, ScheduledFailure.expired);
    });

    test('sends only the entries of the user who came online', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      await h.store.put(
        entry('entry-carol', untilOnline: '@carol:example.org'),
      );
      await h.queue.start();
      expect(h.sent, isEmpty);
      h.online.add('@bob:example.org');
      await pumpEventQueue();
      expect(h.sent, hasLength(1));
      expect(h.store.entries().single.id, 'entry-carol');
    });

    test('a user who is already online is found on the next check', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      h.onlineNow.add('@bob:example.org');
      await h.queue.start();
      expect(h.sent, hasLength(1));
    });

    test('someone else being online changes nothing', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      h.onlineNow.add('@carol:example.org');
      await h.queue.start();
      expect(h.sent, isEmpty);
    });

    test('a wait of more than 30 days fails', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      h.now = base.add(const Duration(days: 31));
      await h.queue.start();
      expect(h.sent, isEmpty);
      expect(h.only().state, ScheduledState.failed);
    });

    test('29 days is still waiting', () async {
      await h.store.put(entry('entry-bob01', untilOnline: '@bob:example.org'));
      h.now = base.add(const Duration(days: 29));
      await h.queue.start();
      expect(h.only().state, ScheduledState.pending);
    });
  });

  group('timer', () {
    testWidgets('a timer sends the entry when it falls due', (tester) async {
      var elapsed = Duration.zero;
      final store = ScheduledStore.forTesting(
        () => h.database,
        now: () => base.add(elapsed),
      );
      final queue = ScheduledQueue(
        store,
        send: (room, content) async => h.sent.add((room, content)),
        now: () => base.add(elapsed),
      );
      await store.put(
        entry('entry-0001', sendAt: base.add(const Duration(minutes: 3))),
      );
      await queue.start();
      await tester.pump();
      expect(h.sent, isEmpty);
      elapsed = const Duration(minutes: 3);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(
        h.sent,
        hasLength(1),
        reason: 'the timer step is at most a minute',
      );
      queue.stop();
    });

    testWidgets('a round that runs while stop is called does not re-arm', (
      tester,
    ) async {
      const elapsed = Duration.zero;
      final gate = Completer<void>();
      final store = ScheduledStore.forTesting(
        () => h.database,
        now: () => base.add(elapsed),
      );
      final queue = ScheduledQueue(
        store,
        send: (room, content) async {
          h.sent.add((room, content));
          await gate.future;
        },
        now: () => base.add(elapsed),
      );
      await store.put(
        entry('entry-0001', sendAt: base.subtract(const Duration(minutes: 1))),
      );
      await store.put(
        entry('entry-0002', sendAt: base.add(const Duration(seconds: 30))),
      );
      unawaited(queue.start());
      await tester.pump();
      queue.stop();
      gate.complete();
      await tester.pump();
      expect(h.sent, hasLength(1));
      expect(
        store.entries().single.id,
        'entry-0002',
        reason: 'a pending timer left behind fails the test',
      );
    });

    test('a stopped queue leaves everything alone', () async {
      await h.store.put(entry('entry-0001'));
      h.now = base.add(const Duration(minutes: 11));
      h.queue.stop();
      await h.queue.evaluate();
      expect(h.sent, isEmpty);
      expect(h.only().state, ScheduledState.pending);
    });

    testWidgets('stop cancels the timer', (tester) async {
      var elapsed = Duration.zero;
      final store = ScheduledStore.forTesting(
        () => h.database,
        now: () => base.add(elapsed),
      );
      final queue = ScheduledQueue(
        store,
        send: (room, content) async => h.sent.add((room, content)),
        now: () => base.add(elapsed),
      );
      await store.put(
        entry('entry-0001', sendAt: base.add(const Duration(seconds: 30))),
      );
      await queue.start();
      await tester.pump();
      queue.stop();
      elapsed = const Duration(minutes: 1);
      await tester.pump(const Duration(minutes: 2));
      expect(h.sent, isEmpty);
    });
  });

  group('per account', () {
    test('every client has its own queue, forget stops it', () async {
      final a = await prepareTestClient(clientName: 'queue-a');
      final b = await prepareTestClient(clientName: 'queue-b');
      final queueA = ScheduledQueue.of(a);
      expect(identical(queueA, ScheduledQueue.of(a)), isTrue);
      expect(identical(queueA, ScheduledQueue.of(b)), isFalse);
      ScheduledQueue.forget(a);
      expect(identical(queueA, ScheduledQueue.of(a)), isFalse);
      ScheduledQueue.forget(a);
      ScheduledQueue.forget(b);
    });

    test('a room the user left is never written to', () async {
      final client = await prepareTestClient(clientName: 'queue-left');
      client.rooms.add(
        Room(id: roomId, client: client, membership: Membership.leave),
      );
      final store = ScheduledStore.forTesting(
        () => client.database,
        now: () => h.now,
      );
      await client.database.cacheCustomObject(ScheduledStore.documentKey, {});
      final queue = ScheduledQueue.forClient(client, store, now: () => h.now);
      await store.put(entry('entry-0001'));
      FakeMatrixApi.calledEndpoints.clear();
      await queue.start();
      expect(store.entries().single.state, ScheduledState.failed);
      expect(
        FakeMatrixApi.calledEndpoints.keys.where((k) => k.contains('/send/')),
        isEmpty,
      );
      queue.stop();
    });

    test('an unknown room fails the entry too', () async {
      final client = await prepareTestClient(clientName: 'queue-unknown');
      await client.database.cacheCustomObject(ScheduledStore.documentKey, {});
      final store = ScheduledStore.forTesting(
        () => client.database,
        now: () => h.now,
      );
      final queue = ScheduledQueue.forClient(client, store, now: () => h.now);
      await store.put(entry('entry-0001'));
      await queue.start();
      expect(store.entries().single.state, ScheduledState.failed);
      queue.stop();
    });
  });
}
