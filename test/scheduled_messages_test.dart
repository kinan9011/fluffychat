// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/scheduling/delayed_events_api.dart';
import 'package:fluffychat/utils/scheduling/scheduled_messages.dart';
import 'package:fluffychat/utils/scheduling/scheduled_queue.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

class _Database implements DatabaseApi {
  Map<String, Object?>? document;
  bool failingWrites = false;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {
    if (failingWrites) throw StateError('SENTINEL-DB-FAILURE');
    document = Map.of(object);
  }

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async =>
      document == null ? null : (content: document!, savedAt: DateTime(2025));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Source implements ServerCapabilitySource {
  _Source(this.features);

  final Map<String, bool> features;
  int fetches = 0;
  Completer<void>? hang;

  @override
  Future<ServerCapabilityInputs> fetch() async {
    fetches++;
    await hang?.future;
    return ServerCapabilityInputs(
      versionsJson: {
        'versions': ['v1.11'],
        'unstable_features': features,
      },
      wellKnownJson: const <String, Object?>{},
      hasAuthMetadata: false,
    );
  }
}

class _Api implements DelayedEventsApi {
  _Api(this.client);

  @override
  final Client client;
  final log = <String>[];
  final listed = <ServerDelayedEvent>[];
  bool complete = true;
  Object? scheduleError;
  Object? cancelError;
  Object? listError;
  Duration? lastDelay;
  var counter = 0;

  @override
  Future<String> scheduleMessage(
    Room room,
    Map<String, Object?> content,
    Duration delay,
  ) async {
    log.add('schedule');
    lastDelay = delay;
    if (scheduleError != null) throw scheduleError!;
    return 'delay-${++counter}';
  }

  @override
  Future<({List<ServerDelayedEvent> events, bool complete})> list() async {
    log.add('list');
    if (listError != null) throw listError!;
    return (events: List.of(listed), complete: complete);
  }

  @override
  Future<void> sendNow(String delayId) async => log.add('send $delayId');

  @override
  Future<void> cancel(String delayId) async {
    log.add('cancel $delayId');
    if (cancelError != null) throw cancelError!;
  }
}

MatrixException matrixError(
  int status,
  String errcode, [
  Map<String, Object?>? extra,
]) => MatrixException(
  http.Response(
    '{"errcode":"$errcode","error":"x"${extra == null ? '' : ',${extra.entries.map((e) => '"${e.key}":${e.value}').join(',')}'}}',
    status,
  ),
);

const roomId = '!a:example.org';
final base = DateTime(2025, 11, 13, 14, 30);
const body = {'msgtype': 'm.text', 'body': 'hello'};

void main() {
  late Client client;
  late Room room;
  late _Database database;
  late ScheduledStore store;
  late _Api api;
  late _Source source;
  late ServerCapabilitiesService capabilities;
  late ScheduledQueue queue;
  late ScheduledMessages messages;
  final sent = <String>[];
  final clients = <bool, Client>{};
  var now = base;

  Future<void> setUpWith({bool supported = true}) async {
    client = clients[supported] ??= await prepareTestClient(
      clientName: 'facade-$supported',
    );
    client.rooms.removeWhere((r) => r.id == roomId);
    room = Room(id: roomId, client: client, membership: Membership.join);
    client.rooms.add(room);
    database = _Database();
    store = ScheduledStore.forTesting(() => database, now: () => now);
    api = _Api(client);
    source = _Source({'org.matrix.msc4140': supported});
    capabilities = ServerCapabilitiesService(sourceFor: (_) => source);
    sent.clear();
    queue = ScheduledQueue(
      store,
      send: (r, c) async => sent.add(r),
      now: () => now,
    );
    messages = ScheduledMessages(
      client,
      capabilities: capabilities,
      api: api,
      store: store,
      queue: queue,
      now: () => now,
      modeTimeout: const Duration(milliseconds: 50),
    );
    now = base;
  }

  Future<ScheduleError?> failure(Future<void> Function() action) async {
    try {
      await action();
    } on ScheduleException catch (e) {
      return e.error;
    }
    return null;
  }

  group('mode', () {
    test('a server with delayed events schedules on the server', () async {
      await setUpWith();
      expect(await messages.modeFor(), ScheduledMode.server);
    });

    test('a server without them uses this device', () async {
      await setUpWith(supported: false);
      expect(await messages.modeFor(), ScheduledMode.device);
    });

    test('partial and unknown support use this device', () async {
      await setUpWith();
      final partial = ServerCapabilitiesService(
        sourceFor: (_) => _PartialSource(),
      );
      final other = ScheduledMessages(
        client,
        capabilities: partial,
        api: api,
        store: store,
        queue: queue,
        modeTimeout: const Duration(milliseconds: 50),
      );
      expect(await other.modeFor(), ScheduledMode.device);
    });

    test('a capability check that hangs falls back to this device', () async {
      await setUpWith();
      source.hang = Completer<void>();
      expect(await messages.modeFor(), ScheduledMode.device);
      source.hang!.complete();
    });
  });

  group('schedule', () {
    test(
      'on the server: one request with the exact delay and a local record',
      () async {
        await setUpWith();
        await messages.schedule(
          room,
          body,
          base.add(const Duration(hours: 2)),
          ScheduledMode.server,
        );
        expect(api.log, ['schedule']);
        expect(api.lastDelay, const Duration(hours: 2));
        final entry = store.entries().single;
        expect(entry.mode, ScheduledMode.server);
        expect(entry.delayId, 'delay-1');
        expect(entry.content, body);
      },
    );

    test('on this device: stored, no request', () async {
      await setUpWith(supported: false);
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 2)),
        ScheduledMode.device,
      );
      expect(api.log, isEmpty);
      expect(store.entries().single.mode, ScheduledMode.device);
    });

    test('too soon and too far are refused before anything happens', () async {
      await setUpWith();
      expect(
        await failure(
          () => messages.schedule(
            room,
            body,
            base.add(const Duration(seconds: 30)),
            ScheduledMode.server,
          ),
        ),
        ScheduleError.tooSoon,
      );
      expect(
        await failure(
          () => messages.schedule(
            room,
            body,
            base.add(const Duration(days: 400)),
            ScheduledMode.server,
          ),
        ),
        ScheduleError.tooFar,
      );
      expect(api.log, isEmpty);
    });

    test('a full store refuses before the server is asked', () async {
      await setUpWith();
      for (var i = 0; i < ScheduledStore.maxEntries; i++) {
        await store.put(
          ScheduledEntry(
            id: 'entry-${i.toString().padLeft(4, '0')}',
            roomId: roomId,
            mode: ScheduledMode.device,
            sendAt: base.add(const Duration(days: 1)),
            createdAt: base,
            content: body,
          ),
        );
      }
      expect(
        await failure(
          () => messages.schedule(
            room,
            body,
            base.add(const Duration(hours: 2)),
            ScheduledMode.server,
          ),
        ),
        ScheduleError.tooMany,
      );
      expect(api.log, isEmpty);
    });

    test(
      'a store that cannot keep the entry cancels the server copy',
      () async {
        await setUpWith();
        database.failingWrites = true;
        expect(
          await failure(
            () => messages.schedule(
              room,
              body,
              base.add(const Duration(hours: 2)),
              ScheduledMode.server,
            ),
          ),
          ScheduleError.storageUnavailable,
        );
        expect(api.log, ['schedule', 'cancel delay-1']);
      },
    );

    test('only the delay guard means too soon', () async {
      await setUpWith();
      final at = base.add(const Duration(hours: 2));
      api.scheduleError = const ScheduleDelayTooShort();
      expect(
        await failure(
          () => messages.schedule(room, body, at, ScheduledMode.server),
        ),
        ScheduleError.tooSoon,
      );
      api.scheduleError = ArgumentError('anything else');
      expect(
        await failure(
          () => messages.schedule(room, body, at, ScheduledMode.server),
        ),
        ScheduleError.failed,
      );
    });

    test('server errors become honest errors', () async {
      await setUpWith();
      final at = base.add(const Duration(hours: 2));
      api.scheduleError = matrixError(400, 'M_MAX_DELAY_EXCEEDED', {
        'max_delay': 864000000,
      });
      Object? caught;
      try {
        await messages.schedule(room, body, at, ScheduledMode.server);
      } on ScheduleException catch (e) {
        caught = e;
      }
      expect((caught! as ScheduleException).error, ScheduleError.tooFar);
      expect((caught as ScheduleException).maxDays, 10);

      final before = source.fetches;
      api.scheduleError = matrixError(404, 'M_UNRECOGNIZED');
      expect(
        await failure(
          () => messages.schedule(room, body, at, ScheduledMode.server),
        ),
        ScheduleError.unsupported,
      );
      await pumpEventQueue();
      expect(
        source.fetches,
        greaterThan(before),
        reason: 'capabilities refreshed',
      );

      api.scheduleError = const ScheduledEncryptionUnavailable();
      expect(
        await failure(
          () => messages.schedule(room, body, at, ScheduledMode.server),
        ),
        ScheduleError.encryptionUnavailable,
      );
      api.scheduleError = StateError('boom');
      expect(
        await failure(
          () => messages.schedule(room, body, at, ScheduledMode.server),
        ),
        ScheduleError.failed,
      );
      expect(store.entries(), isEmpty, reason: 'nothing stored on any failure');
    });
  });

  group('load', () {
    ServerDelayedEvent server(
      String id, {
      String room = roomId,
      String type = 'm.room.message',
    }) => ServerDelayedEvent(
      delayId: id,
      roomId: room,
      type: type,
      sendAt: base.add(const Duration(hours: 3)),
      content: {'msgtype': 'm.text', 'body': 'server $id'},
    );

    Future<void> record(String delayId) => store.put(
      ScheduledEntry(
        id: 'entry-$delayId',
        roomId: roomId,
        mode: ScheduledMode.server,
        sendAt: base.add(const Duration(hours: 3)),
        createdAt: base,
        delayId: delayId,
        content: body,
      ),
    );

    test(
      'a server entry with a local record shows the local text once',
      () async {
        await setUpWith();
        await record('delay-a');
        api.listed.add(server('delay-a'));
        final list = await messages.load(room);
        expect(list.items, hasLength(1));
        expect(list.items.single.local, isNotNull);
        expect(list.items.single.preview, 'hello');
        expect(list.items.single.fromOtherDevice, isFalse);
      },
    );

    test('an entry only the server knows is from another device', () async {
      await setUpWith();
      api.listed.addAll([
        server('delay-x'),
        server('delay-y', room: '!other:example.org'),
        server('delay-z', type: 'm.room.encrypted'),
      ]);
      final list = await messages.load(room);
      expect(list.items.map((i) => i.server?.delayId), ['delay-x', 'delay-z']);
      expect(list.items.first.fromOtherDevice, isTrue);
      expect(list.items.first.preview, 'server delay-x');
      expect(list.items.last.preview, '', reason: 'ciphertext has no text');
      expect(list.items.every((i) => !i.canReschedule), isTrue);
      expect(messages.countFor(roomId), 2);
    });

    test('a record the complete list no longer has is removed', () async {
      await setUpWith();
      await record('delay-gone');
      final list = await messages.load(room);
      expect(list.items, isEmpty);
      expect(store.entries(), isEmpty);
    });

    test('an incomplete list proves nothing, the record stays', () async {
      await setUpWith();
      await record('delay-gone');
      api.complete = false;
      await messages.load(room);
      expect(store.entries(), hasLength(1));
    });

    test('a failing list keeps the local records and says so', () async {
      await setUpWith();
      await record('delay-a');
      api.listError = StateError('offline');
      final list = await messages.load(room);
      expect(list.serverListFailed, isTrue);
      expect(list.items.single.local?.delayId, 'delay-a');
      expect(store.entries(), hasLength(1));
    });

    test('a server without the feature and no records is not asked', () async {
      await setUpWith(supported: false);
      await messages.load(room);
      expect(api.log, isEmpty);
    });

    test('hasFailed reports failed entries of the room only', () async {
      await setUpWith(supported: false);
      await store.put(
        ScheduledEntry(
          id: 'entry-fail1',
          roomId: roomId,
          mode: ScheduledMode.device,
          sendAt: base,
          createdAt: base,
          state: ScheduledState.failed,
          content: body,
        ),
      );
      expect(messages.hasFailed(roomId), isTrue);
      expect(messages.hasFailed('!b:example.org'), isFalse);
    });
  });

  group('a room that is encrypted by now', () {
    void encrypt() => room.setState(
      Event(
        type: EventTypes.Encryption,
        stateKey: '',
        content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
        room: room,
        eventId: r'$enc:example.org',
        senderId: '@test:fakeServer.notExisting',
        originServerTs: DateTime(2025),
      ),
    );

    ServerDelayedEvent listed(String delayId) => ServerDelayedEvent(
      delayId: delayId,
      roomId: roomId,
      type: 'm.room.message',
      sendAt: base.add(const Duration(hours: 3)),
      content: body,
    );

    test('the record knows whether the room was encrypted', () async {
      await setUpWith();
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.server,
      );
      expect(store.entries().single.encrypted, isFalse);
      encrypt();
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 4)),
        ScheduledMode.server,
      );
      expect(store.byDelayId('delay-2')!.encrypted, isTrue);
    });

    test('a plain record in it is marked as sent unencrypted', () async {
      await setUpWith();
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.server,
      );
      api.listed.add(listed('delay-1'));
      expect(
        (await messages.load(room)).items.single.sendsUnencrypted,
        isFalse,
      );
      encrypt();
      final item = (await messages.load(room)).items.single;
      expect(item.sendsUnencrypted, isTrue);
      expect(item.canReschedule, isTrue);
    });

    test('a record made in the encrypted room is not marked', () async {
      await setUpWith();
      encrypt();
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.server,
      );
      api.listed.add(listed('delay-1'));
      expect(
        (await messages.load(room)).items.single.sendsUnencrypted,
        isFalse,
      );
    });

    test('rescheduling schedules it again as encrypted', () async {
      await setUpWith();
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.server,
      );
      encrypt();
      await messages.reschedule(
        ScheduledItem(local: store.entries().single),
        base.add(const Duration(hours: 5)),
      );
      expect(store.entries().single.encrypted, isTrue);
    });
  });

  group('actions', () {
    Future<ScheduledItem> serverItem() async {
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.server,
      );
      api.log.clear();
      return ScheduledItem(local: store.entries().single);
    }

    test(
      'reschedule cancels first, then schedules, then drops the old record',
      () async {
        await setUpWith();
        final item = await serverItem();
        await messages.reschedule(item, base.add(const Duration(hours: 5)));
        expect(api.log, ['cancel delay-1', 'schedule']);
        final entry = store.entries().single;
        expect(entry.delayId, 'delay-2');
        expect(entry.id, item.local!.id);
        expect(entry.sendAt, base.add(const Duration(hours: 5)));
      },
    );

    test(
      'a failed new schedule leaves the text as a failed local entry',
      () async {
        await setUpWith();
        final item = await serverItem();
        api.scheduleError = StateError('offline');
        expect(
          await failure(
            () => messages.reschedule(item, base.add(const Duration(hours: 5))),
          ),
          ScheduleError.failed,
        );
        final entry = store.entries().single;
        expect(entry.state, ScheduledState.failed);
        expect(entry.mode, ScheduledMode.device);
        expect(entry.delayId, isNull);
        expect(entry.content, body);
      },
    );

    test('a failed cancel changes nothing', () async {
      await setUpWith();
      final item = await serverItem();
      api.cancelError = StateError('offline');
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 5))),
        ),
        ScheduleError.failed,
      );
      expect(api.log, ['cancel delay-1']);
      final entry = store.entries().single;
      expect(entry.delayId, 'delay-1');
      expect(entry.mode, ScheduledMode.server);
      expect(entry.state, ScheduledState.pending);
    });

    test('a store that cannot write is found out before the cancel', () async {
      await setUpWith();
      final item = await serverItem();
      database.failingWrites = true;
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 5))),
        ),
        ScheduleError.storageUnavailable,
      );
      expect(api.log, isEmpty);
      database.failingWrites = false;
      expect(store.entries().single.delayId, 'delay-1');
    });

    test('the server already sent it: nothing is scheduled again', () async {
      await setUpWith();
      final item = await serverItem();
      api.cancelError = matrixError(404, 'M_NOT_FOUND');
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 5))),
        ),
        ScheduleError.alreadySent,
      );
      expect(api.log, ['cancel delay-1']);
      expect(store.entries(), isEmpty);
    });

    test('a server record the list already dropped is already sent', () async {
      await setUpWith();
      final item = await serverItem();
      await store.remove(item.local!.id);
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 5))),
        ),
        ScheduleError.alreadySent,
      );
      expect(api.log, isEmpty);
      expect(store.entries(), isEmpty);
    });

    test('a device entry that left meanwhile is not brought back', () async {
      await setUpWith(supported: false);
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.device,
      );
      final item = ScheduledItem(local: store.entries().single);
      await store.remove(item.local!.id);
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 6))),
        ),
        ScheduleError.alreadySent,
      );
      expect(store.entries(), isEmpty);
      expect(sent, isEmpty);
    });

    test('a device entry that is being sent is not moved', () async {
      await setUpWith(supported: false);
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.device,
      );
      final item = ScheduledItem(local: store.entries().single);
      await store.put(item.local!.copyWith(state: ScheduledState.sending));
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 6))),
        ),
        ScheduleError.alreadySent,
      );
      expect(store.entries().single.state, ScheduledState.sending);
      expect(store.entries().single.sendAt, base.add(const Duration(hours: 3)));
    });

    test('a failed device entry can be rescheduled', () async {
      await setUpWith(supported: false);
      await store.put(
        ScheduledEntry(
          id: 'entry-fail1',
          roomId: roomId,
          mode: ScheduledMode.device,
          sendAt: base,
          createdAt: base,
          state: ScheduledState.failed,
          reason: ScheduledFailure.late,
          content: body,
        ),
      );
      await messages.reschedule(
        ScheduledItem(local: store.entries().single),
        base.add(const Duration(hours: 6)),
      );
      final entry = store.entries().single;
      expect(entry.state, ScheduledState.pending);
      expect(entry.reason, isNull);
      expect(entry.sendAt, base.add(const Duration(hours: 6)));
    });

    test('a full store still reschedules, it replaces the entry', () async {
      await setUpWith();
      final item = await serverItem();
      for (var i = 1; i < ScheduledStore.maxEntries; i++) {
        await store.put(
          ScheduledEntry(
            id: 'entry-fill${i.toString().padLeft(3, '0')}',
            roomId: '!other:example.org',
            mode: ScheduledMode.device,
            sendAt: base.add(const Duration(days: 2)),
            createdAt: base,
            content: body,
          ),
        );
      }
      expect(store.entries(), hasLength(ScheduledStore.maxEntries));
      await messages.reschedule(item, base.add(const Duration(hours: 5)));
      expect(api.log, ['cancel delay-1', 'schedule']);
      expect(store.entries(), hasLength(ScheduledStore.maxEntries));
      expect(store.byDelayId('delay-2')?.id, item.local!.id);
    });

    test('a reschedule that fails says rescheduleFailed', () async {
      await setUpWith();
      final item = await serverItem();
      api.scheduleError = StateError('offline');
      await failure(
        () => messages.reschedule(item, base.add(const Duration(hours: 5))),
      );
      expect(store.entries().single.reason, ScheduledFailure.rescheduleFailed);
    });

    test('an entry from another device cannot be rescheduled', () async {
      await setUpWith();
      final item = ScheduledItem(
        server: ServerDelayedEvent(
          delayId: 'delay-x',
          roomId: roomId,
          type: 'm.room.encrypted',
          sendAt: base.add(const Duration(hours: 3)),
          content: const {},
        ),
      );
      expect(
        await failure(
          () => messages.reschedule(item, base.add(const Duration(hours: 5))),
        ),
        ScheduleError.failed,
      );
      expect(api.log, isEmpty);
    });

    test('a device entry gets its new time in place', () async {
      await setUpWith(supported: false);
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.device,
      );
      final item = ScheduledItem(local: store.entries().single);
      await messages.reschedule(item, base.add(const Duration(hours: 6)));
      expect(store.entries().single.sendAt, base.add(const Duration(hours: 6)));
      expect(store.entries().single.id, item.local!.id);
      expect(api.log, isEmpty);
    });

    test('a when-online entry has no time to change', () async {
      await setUpWith(supported: false);
      await messages.scheduleWhenOnline(room, body, '@bob:example.org');
      final item = ScheduledItem(local: store.entries().single);
      expect(item.canReschedule, isFalse);
      expect(item.untilOnline, '@bob:example.org');
    });

    test('delete cancels on the server and removes the record', () async {
      await setUpWith();
      final item = await serverItem();
      await messages.delete(item);
      expect(api.log, ['cancel delay-1']);
      expect(store.entries(), isEmpty);
    });

    test('delete treats an already gone entry as deleted', () async {
      await setUpWith();
      final item = await serverItem();
      api.cancelError = matrixError(404, 'M_NOT_FOUND');
      await messages.delete(item);
      expect(store.entries(), isEmpty);
    });

    test('a failing cancel keeps the record', () async {
      await setUpWith();
      final item = await serverItem();
      api.cancelError = StateError('offline');
      expect(await failure(() => messages.delete(item)), ScheduleError.failed);
      expect(store.entries(), hasLength(1));
    });

    test(
      'send now on the server asks the server and drops the record',
      () async {
        await setUpWith();
        final item = await serverItem();
        await messages.sendNow(item);
        expect(api.log, ['send delay-1']);
        expect(store.entries(), isEmpty);
      },
    );

    test('send now on this device sends through the queue', () async {
      await setUpWith(supported: false);
      await messages.schedule(
        room,
        body,
        base.add(const Duration(hours: 3)),
        ScheduledMode.device,
      );
      await messages.sendNow(ScheduledItem(local: store.entries().single));
      expect(sent, [roomId]);
      expect(store.entries(), isEmpty);
    });
  });
}

class _PartialSource implements ServerCapabilitySource {
  @override
  Future<ServerCapabilityInputs> fetch() async => const ServerCapabilityInputs(
    versionsJson: {
      'versions': ['v1.11'],
    },
    wellKnownJson: <String, Object?>{},
    hasAuthMetadata: false,
  );
}
