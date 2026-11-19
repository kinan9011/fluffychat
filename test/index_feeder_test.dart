// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/search/index_feeder.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/search_kind.dart';

import 'utils/fake_search_database.dart';
import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late FakeSearchDatabase db;
  late MessageIndex index;
  late Room encrypted;
  late Room plain;
  var reads = <String>[];
  var storedEvents = <String, List<Event>>{};

  setUpAll(() async {
    client = await prepareTestClient();
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  late IndexFeeder feeder;

  setUp(() async {
    db = FakeSearchDatabase();
    index = MessageIndex.forTesting(() => db, canPersist: () => false);
    await index.ready;
    client.rooms.clear();
    encrypted = searchRoom(client, '!enc:example.org');
    plain = searchRoom(client, '!plain:example.org', encrypted: false);
    client.rooms
      ..add(encrypted)
      ..add(plain);
    reads = [];
    storedEvents = {};
    feeder = IndexFeeder.forTesting(
      client,
      index,
      reader: (room, limit) async {
        reads.add('${room.id}:$limit');
        return (storedEvents[room.id] ?? []).take(limit).toList();
      },
    );
  });
  tearDown(() => feeder.stop());

  Event text(Room room, int n, {String body = 'hello', String? sender}) =>
      searchEvent(
        room,
        '\$e$n:example.org',
        body: body,
        senderId: sender ?? '@alice:example.org',
      );

  Event redaction(Room room, String target) => Event(
    type: EventTypes.Redaction,
    content: {},
    room: room,
    eventId: r'$red:example.org',
    senderId: '@alice:example.org',
    originServerTs: DateTime.now(),
    redacts: target,
  );

  Event edit(
    Room room,
    String target,
    String body, {
    String? sender,
    DateTime? at,
  }) => searchEvent(
    room,
    r'$edit:example.org',
    at: at,
    body: '* $body',
    senderId: sender ?? '@alice:example.org',
    extra: {
      'm.new_content': {'msgtype': 'm.text', 'body': body},
      'm.relates_to': {'rel_type': 'm.replace', 'event_id': target},
    },
  );

  group('live events', () {
    test('a timeline event is indexed', () async {
      feeder.start();
      client.onTimelineEvent.add(text(encrypted, 1, body: 'Live words'));
      await Future<void>.delayed(Duration.zero);
      expect(index.snapshot().single.text, 'Live words');
    });

    test('a history event is indexed', () async {
      feeder.start();
      client.onHistoryEvent.add(text(encrypted, 2, body: 'Old words'));
      await Future<void>.delayed(Duration.zero);
      expect(index.snapshot().single.text, 'Old words');
    });

    test('start twice does not double the subscriptions', () async {
      feeder
        ..start()
        ..start();
      var adds = 0;
      final probe = MessageIndex.forTesting(() => db, canPersist: () => false);
      await probe.ready;
      final counting = IndexFeeder.forTesting(client, probe)..start();
      client.onTimelineEvent.add(text(encrypted, 3));
      await Future<void>.delayed(Duration.zero);
      adds = probe.length;
      expect(adds, 1);
      await counting.stop();
      expect(index.length, 1);
    });

    test('nothing arrives after stop', () async {
      feeder.start();
      await feeder.stop();
      client.onTimelineEvent.add(text(encrypted, 4));
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('unencrypted rooms are not indexed', () async {
      feeder.start();
      client.onTimelineEvent.add(text(plain, 5));
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('a message that is still encrypted is not indexed', () async {
      feeder.start();
      client.onTimelineEvent.add(
        searchEvent(
          encrypted,
          r'$e6:example.org',
          type: EventTypes.Encrypted,
          body: 'ciphertext',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('an event of a room that is not joined is not indexed', () async {
      final invited = searchRoom(
        client,
        '!invited:example.org',
        membership: Membership.invite,
      );
      client.rooms.add(invited);
      feeder.start();
      client.onTimelineEvent.add(text(invited, 7));
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('an event of an unknown room is not indexed', () async {
      final ghost = searchRoom(client, '!ghost:example.org');
      feeder.start();
      client.onTimelineEvent.add(text(ghost, 8));
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('a redaction removes the message', () async {
      feeder.start();
      client.onTimelineEvent.add(text(encrypted, 9));
      await Future<void>.delayed(Duration.zero);
      client.onTimelineEvent.add(redaction(encrypted, r'$e9:example.org'));
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('an edit by the author changes the text', () async {
      feeder.start();
      client.onTimelineEvent.add(text(encrypted, 10, body: 'old'));
      await Future<void>.delayed(Duration.zero);
      client.onTimelineEvent.add(edit(encrypted, r'$e10:example.org', 'New'));
      await Future<void>.delayed(Duration.zero);
      expect(index.snapshot().single.text, 'New');
    });

    test('an edit by someone else is ignored', () async {
      feeder.start();
      client.onTimelineEvent.add(text(encrypted, 11, body: 'old'));
      await Future<void>.delayed(Duration.zero);
      client.onTimelineEvent.add(
        edit(
          encrypted,
          r'$e11:example.org',
          'injected',
          sender: '@mallory:example.org',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(index.snapshot().single.text, 'old');
    });

    test('an edit does not become an entry of its own', () async {
      feeder.start();
      client.onTimelineEvent.add(edit(encrypted, r'$none:example.org', 'x'));
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('leaving a room removes its entries', () async {
      feeder.start();
      client.onTimelineEvent.add(text(encrypted, 12));
      await Future<void>.delayed(Duration.zero);
      client.onSync.add(
        SyncUpdate(
          nextBatch: 'b',
          rooms: RoomsUpdate(leave: {encrypted.id: LeftRoomUpdate()}),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });

    test('a hostile event never reaches the stream as an error', () async {
      feeder.start();
      client.onTimelineEvent.add(
        searchEvent(
          encrypted,
          r'$e13:example.org',
          body: <String, Object?>{'a': 1},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(index.length, 0);
    });
  });

  group('catchUp', () {
    test('reads the stored events of encrypted rooms only', () async {
      storedEvents[encrypted.id] = [text(encrypted, 1, body: 'Stored')];
      storedEvents[plain.id] = [text(plain, 2)];
      final seen = await feeder.catchUp();
      expect(seen, 1);
      expect(reads, ['${encrypted.id}:200']);
      expect(index.snapshot().single.text, 'Stored');
    });

    test('oldest first: an edit lands after its message', () async {
      storedEvents[encrypted.id] = [
        edit(encrypted, r'$e1:example.org', 'edited'),
        text(encrypted, 1, body: 'original'),
      ];
      await feeder.catchUp();
      expect(index.snapshot().single.text, 'edited');
    });

    test('a second catch-up reads nothing again', () async {
      storedEvents[encrypted.id] = [text(encrypted, 1)];
      await feeder.catchUp();
      expect(reads, hasLength(1));
      await feeder.catchUp();
      expect(reads, hasLength(1));
    });

    test('a catch-up that was cancelled can be run again', () async {
      storedEvents[encrypted.id] = [text(encrypted, 1)];
      final cancel = CancelFlag()..cancel();
      await feeder.catchUp(cancel: cancel);
      expect(reads, isEmpty);
      await feeder.catchUp();
      expect(index.snapshot(), hasLength(1));
    });

    test('cancelled after its last event it is not done either', () async {
      storedEvents[encrypted.id] = [
        for (var n = 1; n <= IndexFeeder.yieldEvery; n++) text(encrypted, n),
      ];
      final cancel = CancelFlag();
      final running = feeder.catchUp(cancel: cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await running;
      expect(feeder.isCaughtUp, isFalse);
      await feeder.catchUp();
      expect(reads, hasLength(2));
      expect(feeder.isCaughtUp, isTrue);
    });

    test('after the user wiped the index nothing is read back', () async {
      storedEvents[encrypted.id] = [text(encrypted, 1)];
      feeder.markCaughtUp();
      await feeder.catchUp();
      expect(reads, isEmpty);
      expect(index.length, 0);
    });

    test('a wipe while it runs stops it', () async {
      storedEvents[encrypted.id] = [
        for (var n = 1; n <= IndexFeeder.yieldEvery * 2; n++)
          text(encrypted, n),
      ];
      final running = feeder.catchUp();
      await Future<void>.delayed(Duration.zero);
      await index.wipe();
      await running;
      expect(index.length, 0);
    });

    test('newest first, as back-pagination delivers them', () async {
      final base = DateTime(2030);
      feeder.start();
      client.onHistoryEvent
        ..add(
          edit(
            encrypted,
            r'$e1:example.org',
            'second',
            at: base.add(const Duration(minutes: 2)),
          ),
        )
        ..add(
          edit(
            encrypted,
            r'$e1:example.org',
            'first',
            at: base.add(const Duration(minutes: 1)),
          ),
        )
        ..add(text(encrypted, 1, body: 'original'));
      await Future<void>.delayed(Duration.zero);
      expect(index.snapshot().single.text, 'second');
    });

    test('is idempotent', () async {
      storedEvents[encrypted.id] = [text(encrypted, 1)];
      await feeder.catchUp();
      await feeder.catchUp();
      expect(index.length, 1);
    });

    test('honours maxRooms and perRoom', () async {
      client.rooms.remove(encrypted);
      for (var n = 0; n < 5; n++) {
        final room = searchRoom(client, '!r$n:example.org');
        client.rooms.add(room);
        storedEvents[room.id] = [
          for (var i = 0; i < 10; i++) text(room, n * 100 + i),
        ];
      }
      await feeder.catchUp(maxRooms: 2, perRoom: 3);
      expect(reads.length, 2);
      expect(reads.every((r) => r.endsWith(':3')), isTrue);
      expect(index.length, 6);
    });

    test('honours maxEvents', () async {
      storedEvents[encrypted.id] = [
        for (var i = 1; i <= 100; i++) text(encrypted, i),
      ];
      final seen = await feeder.catchUp(maxEvents: 30);
      expect(seen, 30);
      expect(index.length, 30);
    });

    test('stops when cancelled', () async {
      storedEvents[encrypted.id] = [
        for (var i = 1; i <= 200; i++) text(encrypted, i),
      ];
      final cancel = CancelFlag();
      final future = feeder.catchUp(cancel: cancel);
      cancel.cancel();
      final seen = await future;
      expect(seen, lessThan(200));
    });

    test('gives the event loop back while it works', () async {
      storedEvents[encrypted.id] = [
        for (var i = 1; i <= 200; i++) text(encrypted, i),
      ];
      var ticks = 0;
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      await feeder.catchUp();
      timer.cancel();
      expect(ticks, greaterThan(0));
    });

    test('a room that was left while reading is skipped', () async {
      final room = searchRoom(client, '!left:example.org');
      client.rooms.add(room);
      final other = IndexFeeder.forTesting(
        client,
        index,
        reader: (r, limit) async {
          client.rooms.remove(room);
          return [text(room, 77)];
        },
      );
      encrypted.membership = Membership.leave;
      await other.catchUp();
      expect(index.length, 0);
    });
  });

  group('after logout', () {
    test(
      'a client that logs out before its first sync stops waiting',
      () async {
        final fresh = await prepareTestClient(
          clientName: 'NoSync',
          waitForFirstSync: false,
        );
        addTearDown(() => fresh.dispose(closeDatabase: true));
        expect(fresh.prevBatch, isNull);
        final room = searchRoom(fresh, '!late:example.org');
        fresh.rooms.add(room);
        var read = false;
        final late = IndexFeeder.forTesting(
          fresh,
          MessageIndex.forTesting(() => db, canPersist: () => false),
          reader: (room, limit) async {
            read = true;
            return const [];
          },
        );
        var done = false;
        unawaited(late.catchUpAfterFirstSync().then((_) => done = true));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(done, isFalse);
        fresh.onLoginStateChanged.add(LoginState.loggedOut);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(done, isTrue);
        fresh.onSyncStatus.add(const SyncStatusUpdate(SyncStatus.finished));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(read, isFalse);
      },
    );

    test(
      'forgetting the index of a client ends its listener on the cache',
      () async {
        final other = await prepareTestClient(clientName: 'Forgotten');
        addTearDown(() => other.dispose(closeDatabase: true));
        final forgotten = MessageIndex.of(other);
        await forgotten.ready;
        forgotten.add(
          IndexedMessage(
            roomId: '!a:example.org',
            eventId: r'$e1:example.org',
            senderId: '@alice:example.org',
            timestamp: 1700000000000,
            kind: SearchKind.text,
            text: 'words',
          ),
        );
        await forgotten.flush();
        MessageIndex.forget(other);
        await other.database.cacheCustomObject(MessageIndex.documentKey, {
          'v': 1,
          'e': <Object?>[
            [
              '!b:example.org',
              r'$e2:example.org',
              '@a:example.org',
              1,
              0,
              0,
              'kept',
            ],
          ],
        });
        other.onCacheCleared.add(true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final stored = await other.database.getCustomCacheObject(
          MessageIndex.documentKey,
        );
        expect(jsonEncode(stored?.content), contains('kept'));
      },
    );
  });
}
