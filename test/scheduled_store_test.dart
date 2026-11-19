// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

class _Database implements DatabaseApi {
  _Database(this.real);

  final DatabaseApi real;
  final writes = <String>[];
  int failingReads = 0;
  bool failingWrites = false;

  @override
  Future<void> cacheCustomObject(String cacheKey, Map<String, Object?> object) {
    if (failingWrites) throw StateError('SENTINEL-DB-FAILURE');
    writes.add(cacheKey);
    return real.cacheCustomObject(cacheKey, object);
  }

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) {
    if (failingReads <= 0) return real.getCustomCacheObject(cacheKey);
    failingReads--;
    throw StateError('SENTINEL-DB-FAILURE');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const roomId = '!a:example.org';
final now = DateTime(2025, 11, 13, 14, 30);

Map<String, Object?> content([String body = 'hello']) => {
  'msgtype': 'm.text',
  'body': body,
};

ScheduledEntry entry(
  String id, {
  String room = roomId,
  ScheduledMode mode = ScheduledMode.device,
  DateTime? sendAt,
  String? untilOnline,
  String? delayId,
  ScheduledState state = ScheduledState.pending,
  ScheduledFailure? reason,
  bool encrypted = false,
  Map<String, Object?>? body,
}) => ScheduledEntry(
  id: id,
  roomId: room,
  mode: mode,
  sendAt: untilOnline == null
      ? sendAt ?? now.add(const Duration(hours: 1))
      : null,
  untilOnline: untilOnline,
  createdAt: now,
  delayId: delayId,
  state: state,
  reason: reason,
  encrypted: encrypted,
  content: body ?? content(),
);

Map<String, Object?> json(ScheduledEntry e) => e.toJson();

void main() {
  late Client client;
  late _Database database;
  late ScheduledStore store;

  ScheduledStore open() =>
      ScheduledStore.forTesting(() => database, now: () => now);

  Future<void> storeDocument(Object? entries, {int version = 1}) =>
      database.real.cacheCustomObject(ScheduledStore.documentKey, {
        'v': version,
        'entries': entries,
      });

  setUp(() async {
    client = await prepareTestClient();
    database = _Database(client.database);
    await client.database.cacheCustomObject(ScheduledStore.documentKey, {});
    store = open();
    await store.ready;
  });

  test('an entry survives a restart', () async {
    await store.put(entry('entry-0001'));
    final restarted = open();
    await restarted.ready;
    expect(restarted.entries().single.id, 'entry-0001');
    expect(restarted.entries().single.content, content());
  });

  test(
    'plaintext only goes through the database, never the preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      await store.put(entry('entry-0001', body: content('SENTINEL-PLAIN-1')));
      expect(database.writes.toSet(), {ScheduledStore.documentKey});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test('entries are sorted: when online first, then by time', () async {
    await store.put(
      entry('entry-late1', sendAt: now.add(const Duration(days: 2))),
    );
    await store.put(
      entry('entry-soon1', sendAt: now.add(const Duration(hours: 2))),
    );
    await store.put(entry('entry-onl01', untilOnline: '@bob:example.org'));
    expect(store.entries().map((e) => e.id), [
      'entry-onl01',
      'entry-soon1',
      'entry-late1',
    ]);
  });

  test('entries can be filtered by room and found by delay id', () async {
    await store.put(entry('entry-0001'));
    await store.put(
      entry(
        'entry-0002',
        room: '!b:example.org',
        mode: ScheduledMode.server,
        delayId: 'delay-abc',
      ),
    );
    expect(store.entries(roomId: '!b:example.org').single.id, 'entry-0002');
    expect(store.byDelayId('delay-abc')?.id, 'entry-0002');
    expect(store.byDelayId('other'), isNull);
  });

  test('remove erases the plaintext from the stored document', () async {
    await store.put(entry('entry-0001', body: content('SENTINEL-PLAIN-2')));
    await store.remove('entry-0001');
    final stored = await database.real.getCustomCacheObject(
      ScheduledStore.documentKey,
    );
    expect(jsonEncode(stored?.content), isNot(contains('SENTINEL')));
    expect(store.entries(), isEmpty);
  });

  test('a cleared SDK cache does not drop the entries', () async {
    final live = ScheduledStore.of(client);
    await live.ready;
    await live.put(entry('entry-0001'));
    await client.database.clearCache();
    client.onCacheCleared.add(true);
    await pumpEventQueue();
    await live.flush();
    final restarted = ScheduledStore.forTesting(
      () => client.database,
      now: () => now,
    );
    await restarted.ready;
    expect(restarted.entries().single.id, 'entry-0001');
    ScheduledStore.forget(client);
  });

  group('loading a stored document', () {
    Future<List<ScheduledEntry>> load(
      Object? entries, {
      int version = 1,
    }) async {
      await storeDocument(entries, version: version);
      final loaded = open();
      await loaded.ready;
      return loaded.entries();
    }

    test('a valid entry is read', () async {
      expect(await load([json(entry('entry-0001'))]), hasLength(1));
    });

    test('another document version is ignored', () async {
      expect(await load([json(entry('entry-0001'))], version: 2), isEmpty);
    });

    test('a document that is not a list of maps is ignored', () async {
      expect(await load('nope'), isEmpty);
      expect(await load([1, 'a', null]), isEmpty);
    });

    test('invalid entries are dropped one by one, valid ones stay', () async {
      Map<String, Object?> with_(String key, Object? value) => {
        ...json(entry('entry-bad001')),
        key: value,
      };
      final loaded = await load([
        json(entry('entry-good01')),
        with_('room', 'not-a-room'),
        with_('id', 'x'),
        with_('id', 'has space in it'),
        with_('mode', 'other'),
        with_('state', 'zombie'),
        with_('content', null),
        with_('content', {'msgtype': 'm.image', 'body': 'x'}),
        with_('delay', 'delay-on-device'),
        with_('at', now.add(const Duration(days: 400)).millisecondsSinceEpoch),
        with_('created', 'yesterday'),
        with_('online', '@bob:example.org'),
      ]);
      expect(loaded.map((e) => e.id), ['entry-good01']);
    });

    test('a server entry needs a valid delay id', () async {
      final server = json(
        entry('entry-0001', mode: ScheduledMode.server, delayId: 'delay-abc'),
      );
      expect(await load([server]), hasLength(1));
      expect(
        await load([
          {...server, 'delay': null},
        ]),
        isEmpty,
      );
      expect(
        await load([
          {...server, 'delay': 'has space'},
        ]),
        isEmpty,
      );
      expect(
        await load([
          {...server, 'delay': 'a' * 256},
        ]),
        isEmpty,
      );
      for (final bad in ['a/b', '..', '.', 'a?b', 'a#b', 'a%2Fb', 'ä']) {
        expect(
          await load([
            {...server, 'delay': bad},
          ]),
          isEmpty,
          reason: bad,
        );
      }
    });

    test('a when-online entry has a partner and no time', () async {
      final online = json(entry('entry-0001', untilOnline: '@bob:example.org'));
      expect(await load([online]), hasLength(1));
      expect(
        await load([
          {...online, 'online': 'bob'},
        ]),
        isEmpty,
      );
      expect(
        await load([
          {...online, 'online': null},
        ]),
        isEmpty,
      );
    });

    test('a room version 12 room id is accepted', () async {
      final v12 = '!${'a' * 43}';
      expect(await load([json(entry('entry-0001', room: v12))]), hasLength(1));
    });

    test('unknown content keys are stripped', () async {
      final loaded = await load([
        {
          ...json(entry('entry-0001')),
          'content': {...content(), 'url': 'mxc://evil/x'},
        },
      ]);
      expect(loaded.single.content, content());
    });

    test('an oversize body drops the entry', () async {
      final loaded = await load([
        json(entry('entry-0001', body: content('a' * 30000))),
      ]);
      expect(loaded, isEmpty);
    });

    test('more than the cap keeps the earliest entries', () async {
      final loaded = await load([
        for (var i = 0; i < ScheduledStore.maxEntries + 1; i++)
          json(
            entry(
              'entry-${i.toString().padLeft(4, '0')}',
              sendAt: now.add(Duration(minutes: 10 + i)),
            ),
          ),
      ]);
      expect(loaded, hasLength(ScheduledStore.maxEntries));
      expect(loaded.map((e) => e.id), isNot(contains('entry-0100')));
    });

    test('an entry that was sending when the app died is failed', () async {
      final loaded = await load([
        json(entry('entry-0001', state: ScheduledState.sending)),
      ]);
      expect(loaded.single.state, ScheduledState.failed);
    });
  });

  group('caps', () {
    test('the 101st new entry is refused, an update is not', () async {
      for (var i = 0; i < ScheduledStore.maxEntries; i++) {
        await store.put(entry('entry-${i.toString().padLeft(4, '0')}'));
      }
      await expectLater(
        store.put(entry('entry-over01')),
        throwsA(isA<ScheduledCapReached>()),
      );
      await store.put(entry('entry-0000', state: ScheduledState.failed));
      expect(store.entries(), hasLength(ScheduledStore.maxEntries));
      expect(
        store.entries().firstWhere((e) => e.id == 'entry-0000').state,
        ScheduledState.failed,
      );
    });

    test('the document byte cap refuses a new entry', () async {
      Map<String, Object?> big() => {
        ...content('a' * 24000),
        'format': 'org.matrix.custom.html',
        'formatted_body': 'b' * 24000,
      };
      await storeDocument([
        for (var i = 0; i < 80; i++)
          json(entry('seed-${i.toString().padLeft(4, '0')}', body: big())),
      ]);
      final seeded = open();
      await seeded.ready;
      expect(seeded.entries(), hasLength(80));
      var added = 0;
      Object? refused;
      for (var i = 0; i < 20 && refused == null; i++) {
        try {
          await seeded.put(
            entry('entry-${i.toString().padLeft(4, '0')}', body: big()),
          );
          added++;
        } on ScheduledCapReached catch (e) {
          refused = e;
        }
      }
      expect(refused, isA<ScheduledCapReached>());
      expect(added, lessThan(20));
    });
  });

  group('storage failures', () {
    test('an unreadable document is never overwritten', () async {
      await store.put(entry('entry-0001'));
      database.writes.clear();
      database.failingReads = 99;
      final broken = open();
      await broken.ready;
      await expectLater(
        broken.put(entry('entry-0002')),
        throwsA(isA<ScheduledStorageUnavailable>()),
      );
      expect(database.writes, isEmpty);
      expect(broken.entries(), isEmpty);
    });

    test('a document that becomes readable keeps its entries', () async {
      await store.put(entry('entry-0001'));
      database.failingReads = 1;
      final late = open();
      await late.ready;
      await late.put(entry('entry-0002'));
      final restarted = open();
      await restarted.ready;
      expect(restarted.entries().map((e) => e.id).toSet(), {
        'entry-0001',
        'entry-0002',
      });
    });

    test('a failed write is reported and rolled back', () async {
      database.failingWrites = true;
      await expectLater(
        store.put(entry('entry-0001')),
        throwsA(isA<ScheduledStorageUnavailable>()),
      );
      expect(store.entries(), isEmpty);
    });

    test('failure logs carry no text of the message', () async {
      Logs().outputEvents.clear();
      database.failingWrites = true;
      try {
        await store.put(entry('entry-0001', body: content('SENTINEL-PLAIN-3')));
      } catch (e) {
        expect(e.toString(), isNot(contains('SENTINEL')));
      }
      for (final event in Logs().outputEvents) {
        expect(event.title, isNot(contains('SENTINEL')));
        expect('${event.exception}', isNot(contains('SENTINEL-PLAIN')));
      }
    });
  });

  group('failure reason', () {
    Future<List<ScheduledEntry>> load(Object? entries) async {
      await storeDocument(entries);
      final loaded = open();
      await loaded.ready;
      return loaded.entries();
    }

    test('every reason survives a restart', () async {
      for (final reason in ScheduledFailure.values) {
        await store.put(
          entry(
            'entry-${reason.name}',
            state: ScheduledState.failed,
            reason: reason,
          ),
        );
      }
      final restarted = open();
      await restarted.ready;
      expect(
        {for (final e in restarted.entries()) e.id: e.reason},
        {for (final r in ScheduledFailure.values) 'entry-${r.name}': r},
      );
    });

    test(
      'an unknown or missing reason on a failed entry is a send failure',
      () async {
        final failed = json(entry('entry-0001', state: ScheduledState.failed));
        expect(
          (await load([
            {...failed, 'reason': 'SENTINEL-NOT-A-REASON'},
          ])).single.reason,
          ScheduledFailure.sendFailed,
        );
        expect(
          (await load([
            {...failed, 'reason': 7},
          ])).single.reason,
          ScheduledFailure.sendFailed,
        );
        expect(
          (await load([failed])).single.reason,
          ScheduledFailure.sendFailed,
        );
      },
    );

    test('only a failed entry has a reason', () async {
      final pending = json(entry('entry-0001'));
      expect(
        (await load([
          {...pending, 'reason': 'late'},
        ])).single.reason,
        isNull,
      );
    });

    test('an entry that was sending when the app died says so', () async {
      final loaded = await load([
        json(entry('entry-0001', state: ScheduledState.sending)),
      ]);
      expect(loaded.single.reason, ScheduledFailure.sendFailed);
    });

    test('a state change away from failed drops the reason', () async {
      final failed = entry(
        'entry-0001',
        state: ScheduledState.failed,
        reason: ScheduledFailure.late,
      );
      expect(failed.copyWith(state: ScheduledState.pending).reason, isNull);
      expect(
        entry('entry-0002')
            .copyWith(
              state: ScheduledState.failed,
              reason: ScheduledFailure.expired,
            )
            .reason,
        ScheduledFailure.expired,
      );
    });
  });

  group('encrypted flag', () {
    test('is kept, and absent means not encrypted', () async {
      await store.put(
        entry(
          'entry-0001',
          mode: ScheduledMode.server,
          delayId: 'delay-1',
          encrypted: true,
        ),
      );
      final restarted = open();
      await restarted.ready;
      expect(restarted.entries().single.encrypted, isTrue);
      final bare = json(entry('entry-0002'))..remove('encrypted');
      await storeDocument([bare]);
      final other = open();
      await other.ready;
      expect(other.entries().single.encrypted, isFalse);
    });

    test('a value that is not a bool drops the entry', () async {
      await storeDocument([
        {...json(entry('entry-0001')), 'encrypted': 'yes'},
      ]);
      final loaded = open();
      await loaded.ready;
      expect(loaded.entries(), isEmpty);
    });
  });

  group('update', () {
    test('changes the stored entry and returns it', () async {
      await store.put(entry('entry-0001'));
      final changed = await store.update(
        'entry-0001',
        (current) => current.copyWith(state: ScheduledState.sending),
      );
      expect(changed?.state, ScheduledState.sending);
      expect(store.entries().single.state, ScheduledState.sending);
    });

    test('sees what an earlier queued remove did', () async {
      await store.put(entry('entry-0001'));
      final removal = store.remove('entry-0001');
      final changed = await store.update(
        'entry-0001',
        (current) => current.copyWith(state: ScheduledState.sending),
      );
      await removal;
      expect(changed, isNull);
      expect(store.entries(), isEmpty);
    });

    test('a null answer changes nothing', () async {
      await store.put(entry('entry-0001'));
      database.writes.clear();
      expect(await store.update('entry-0001', (_) => null), isNull);
      expect(await store.update('entry-0404', (c) => c), isNull);
      expect(database.writes, isEmpty);
    });

    test('an entry of another id is refused', () async {
      await store.put(entry('entry-0001'));
      await expectLater(
        store.update('entry-0001', (_) => entry('entry-0002')),
        throwsArgumentError,
      );
      expect(store.entries().single.id, 'entry-0001');
    });

    test('a failed write is rolled back and reported', () async {
      await store.put(entry('entry-0001'));
      database.failingWrites = true;
      await expectLater(
        store.update(
          'entry-0001',
          (current) => current.copyWith(state: ScheduledState.sending),
        ),
        throwsA(isA<ScheduledStorageUnavailable>()),
      );
      expect(store.entries().single.state, ScheduledState.pending);
    });
  });

  test('put refuses an entry that does not validate', () async {
    await expectLater(
      store.put(entry('entry-0001', room: 'not-a-room')),
      throwsArgumentError,
    );
    expect(store.entries(), isEmpty);
  });
}
