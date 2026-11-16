// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

class _ThrowingDatabase implements DatabaseApi {
  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) => throw StateError('SENTINEL-DB-FAILURE');

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) =>
      throw StateError('SENTINEL-DB-FAILURE');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _WriteFailingDatabase implements DatabaseApi {
  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) => throw StateError('SENTINEL-DB-FAILURE');

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FlakyDatabase implements DatabaseApi {
  _FlakyDatabase(this.real, {required this.failingReads});

  final DatabaseApi real;
  int failingReads;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) => real.cacheCustomObject(cacheKey, object);

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

Future<Map<String, Object?>?> persisted(Client client) async =>
    (await client.database.getCustomCacheObject(
      DraftStore.documentKey,
    ))?.content;

DraftStore fresh(Client client) => DraftStore.forTesting(() => client.database);

void main() {
  late Client client;
  late DraftStore store;
  const room = '!a:example.org';

  setUp(() async {
    client = await prepareTestClient();
    await client.database.cacheCustomObject(DraftStore.documentKey, {});
    store = DraftStore.of(client);
    await store.ready;
  });

  test('write then read', () async {
    await store.write(room, '  hello\nworld  ');
    expect(store.read(room)?.text, '  hello\nworld  ');
    expect(store.readForDisplay(room), '  hello\nworld  ');
    expect(store.read('!missing:example.org'), isNull);
  });

  test(
    'a draft survives a restart: a fresh store reads the database',
    () async {
      await store.write(room, 'persisted', format: {'r': true});
      await store.flush();
      final restarted = fresh(client);
      await restarted.ready;
      expect(restarted.read(room)?.text, 'persisted');
      expect(restarted.read(room)?.format, {'r': true});
    },
  );

  test('a cleared SDK cache does not drop the drafts', () async {
    await store.write(room, 'survives a cache clear');
    await store.flush();
    await client.database.clearCache();
    final wiped = fresh(client);
    await wiped.ready;
    expect(wiped.read(room), isNull, reason: 'the SDK wiped the document');
    client.onCacheCleared.add(true);
    await pumpEventQueue();
    await store.flush();
    final restarted = fresh(client);
    await restarted.ready;
    expect(restarted.read(room)?.text, 'survives a cache clear');
  });

  test('remove erases the text from the persisted document', () async {
    await store.write(room, 'SENTINEL-DRAFT-7f3');
    await store.flush();
    expect(jsonEncode(await persisted(client)), contains('SENTINEL-DRAFT-7f3'));
    await store.remove(room);
    await store.flush();
    expect(jsonEncode(await persisted(client)), isNot(contains('SENTINEL')));
    final restarted = fresh(client);
    await restarted.ready;
    expect(restarted.read(room), isNull);
  });

  test('room ids without a server part (room version 12) are valid', () async {
    final v12 = '!${'a1_-' * 10}abc';
    expect(v12.length, 44);
    expect(DraftStore.isRoomId(v12), isTrue);
    expect(DraftStore.isRoomId('!${'a' * 42}'), isFalse);
    expect(DraftStore.isRoomId('!${'a' * 44}'), isFalse);
    expect(DraftStore.isRoomId('!${'a' * 42}:'), isFalse);
    expect(DraftStore.isRoomId('room:server.org'), isFalse);
    await store.write(v12, 'typed in a new room');
    await store.flush();
    final restarted = fresh(client);
    await restarted.ready;
    expect(restarted.read(v12)?.text, 'typed in a new room');
  });

  test('a blank write removes the draft', () async {
    await store.write(room, 'x');
    await store.write(room, ' \n ');
    expect(store.read(room), isNull);
    expect(store.readForDisplay(room), isNull);
  });

  test('the revision moves on write and on remove', () async {
    final start = DraftStore.revision.value;
    await store.write(room, 'x');
    expect(DraftStore.revision.value, start + 1);
    await store.remove(room);
    expect(DraftStore.revision.value, start + 2);
  });

  test('preview collapses whitespace and cuts at 120 clusters', () {
    expect(DraftStore.preview('a\n\n b   c'), 'a b c');
    expect(DraftStore.preview('a' * 200).length, 120);
    final family = '\u{1F468}‍\u{1F469}‍\u{1F467}' * 130;
    expect(DraftStore.preview(family), '\u{1F468}‍\u{1F469}‍\u{1F467}' * 120);
  });

  test('two accounts do not share drafts for the same room id', () async {
    final other = await prepareTestClient(clientName: 'second-account');
    final otherStore = DraftStore.of(other);
    await otherStore.ready;
    await store.write(room, 'typed as the first account');
    await store.flush();
    expect(otherStore.read(room), isNull);
    await otherStore.write(room, 'typed as the second account');
    await otherStore.flush();
    expect(store.read(room)?.text, 'typed as the first account');
    final restarted = fresh(other);
    await restarted.ready;
    expect(restarted.read(room)?.text, 'typed as the second account');
  });

  test('no draft preference is ever written', () async {
    await store.write(room, 'x');
    await store.flush();
    await store.remove(room);
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('draft_')), isEmpty);
  });

  test('draft text never reaches the log', () async {
    Logs().outputEvents.clear();
    await store.write(room, 'SENTINEL-DRAFT-7f3');
    store.read(room);
    store.readForDisplay(room);
    DraftStore.preview('SENTINEL-DRAFT-7f3');
    await store.flush();
    await store.remove(room);
    await store.flush();
    for (final event in Logs().outputEvents) {
      expect(event.title, isNot(contains('SENTINEL')));
      expect('${event.exception}', isNot(contains('SENTINEL')));
      expect('${event.stackTrace}', isNot(contains('SENTINEL')));
    }
  });

  test(
    'a failing database keeps the draft in memory and logs no content',
    () async {
      Logs().outputEvents.clear();
      final broken = DraftStore.forTesting(_ThrowingDatabase.new);
      await broken.ready;
      await broken.write(room, 'SENTINEL-DRAFT-7f3');
      await broken.flush();
      expect(broken.read(room)?.text, 'SENTINEL-DRAFT-7f3');
      final messages = Logs().outputEvents.map((e) => e.title).toList();
      expect(messages, contains('[Drafts] storage unavailable'));
      for (final event in Logs().outputEvents) {
        expect(event.title, isNot(contains('SENTINEL')));
        expect('${event.exception}', isNot(contains('SENTINEL')));
      }
    },
  );

  test(
    'a failing write keeps the draft in memory and logs no content',
    () async {
      Logs().outputEvents.clear();
      final broken = DraftStore.forTesting(_WriteFailingDatabase.new);
      await broken.ready;
      await broken.write(room, 'SENTINEL-DRAFT-7f3');
      await broken.flush();
      expect(broken.read(room)?.text, 'SENTINEL-DRAFT-7f3');
      expect(
        Logs().outputEvents.map((e) => e.title),
        contains('[Drafts] storage unavailable'),
      );
      for (final event in Logs().outputEvents) {
        expect(event.title, isNot(contains('SENTINEL')));
        expect('${event.exception}', isNot(contains('SENTINEL')));
      }
    },
  );

  group('a failed load', () {
    const other = '!b:example.org';

    Future<void> seed() =>
        client.database.cacheCustomObject(DraftStore.documentKey, {
          'v': 1,
          'drafts': {
            other: {'t': 'older draft', 'ts': 1},
          },
        });

    test('is retried before the next write, so no draft is lost', () async {
      await seed();
      final flaky = _FlakyDatabase(client.database, failingReads: 1);
      final loaded = DraftStore.forTesting(() => flaky);
      await loaded.ready;
      expect(loaded.read(other), isNull);
      await loaded.write(room, 'typed after the failure');
      await loaded.flush();
      final stored = fresh(client);
      await stored.ready;
      expect(stored.read(other)?.text, 'older draft');
      expect(stored.read(room)?.text, 'typed after the failure');
    });

    test('does not stop a remove: the stored draft goes too', () async {
      await client.database.cacheCustomObject(DraftStore.documentKey, {
        'v': 1,
        'drafts': {
          room: {'t': 'sent already', 'ts': 2},
          other: {'t': 'older draft', 'ts': 1},
        },
      });
      final flaky = _FlakyDatabase(client.database, failingReads: 1);
      final loaded = DraftStore.forTesting(() => flaky);
      await loaded.ready;
      await loaded.remove(room);
      await loaded.flush();
      final stored = fresh(client);
      await stored.ready;
      expect(stored.read(room), isNull);
      expect(stored.read(other)?.text, 'older draft');
    });

    test('while it stays unreadable nothing is written over it', () async {
      await seed();
      final flaky = _FlakyDatabase(client.database, failingReads: 1000);
      final loaded = DraftStore.forTesting(() => flaky);
      await loaded.ready;
      await loaded.write(room, 'only in memory');
      await loaded.remove('!c:example.org');
      await loaded.flush();
      expect(loaded.read(room)?.text, 'only in memory');
      final stored = fresh(client);
      await stored.ready;
      expect(stored.read(other)?.text, 'older draft');
      expect(stored.read(room), isNull);
      expect(await loaded.importLegacy('!d:example.org', 'legacy'), isFalse);
      final again = fresh(client);
      await again.ready;
      expect(again.read(other)?.text, 'older draft');
      expect(again.read('!d:example.org'), isNull);
    });
  });

  group('hostile stored documents', () {
    Future<DraftStore> loadFrom(Map<String, Object?> document) async {
      await client.database.cacheCustomObject(DraftStore.documentKey, document);
      final loaded = fresh(client);
      await loaded.ready;
      return loaded;
    }

    test('wrong version or shape loads as empty', () async {
      expect((await loadFrom({'v': 2, 'drafts': {}})).read(room), isNull);
      expect((await loadFrom({'v': 1, 'drafts': []})).read(room), isNull);
      expect((await loadFrom({'v': 1})).read(room), isNull);
      expect((await loadFrom({})).read(room), isNull);
    });

    test('entries are validated, capped and cut', () async {
      final drafts = <String, Object?>{
        for (var i = 0; i < 60; i++)
          '!r$i:example.org': {'t': 'text $i', 'ts': i},
        '!bad': {'t': 'x', 'ts': 1000},
        '!blank:example.org': {'t': '   ', 'ts': 1001},
        '!long:example.org': {'t': 'a' * 100000, 'ts': 1002},
        '!fmt:example.org': {
          't': 'y',
          'ts': 1003,
          'f': {'m': 'z' * 20000},
        },
        '!type:example.org': {'t': 5, 'ts': 1004},
      };
      final loaded = await loadFrom({'v': 1, 'drafts': drafts});
      expect(loaded.read('!bad'), isNull);
      expect(loaded.read('!blank:example.org'), isNull);
      expect(loaded.read('!type:example.org'), isNull);
      expect(loaded.read('!long:example.org')?.text.length, 8000);
      expect(loaded.read('!fmt:example.org')?.text, 'y');
      expect(loaded.read('!fmt:example.org')?.format, isNull);
      expect(loaded.read('!r0:example.org'), isNull, reason: 'oldest dropped');
      expect(loaded.read('!r59:example.org')?.text, 'text 59');
    });
  });

  test(
    'the persisted document never exceeds 1 MiB: oldest drafts go first',
    () async {
      var clock = 0;
      final capped = DraftStore.forTesting(
        () => client.database,
        now: () => clock++,
      );
      await capped.ready;
      final big = '😀' * DraftStore.maxDraftChars;
      for (var i = 0; i < 50; i++) {
        await capped.write('!r$i:example.org', '$i$big');
      }
      await capped.flush();
      final document = jsonEncode(await persisted(client));
      expect(
        utf8.encode(document).length,
        lessThanOrEqualTo(DraftStore.maxDocumentBytes),
      );
      expect(capped.read('!r49:example.org'), isNotNull);
      expect(capped.read('!r0:example.org'), isNull);
    },
  );

  test('at most 50 drafts are kept', () async {
    var clock = 0;
    final capped = DraftStore.forTesting(
      () => client.database,
      now: () => clock++,
    );
    await capped.ready;
    for (var i = 0; i < 55; i++) {
      await capped.write('!r$i:example.org', 'x$i');
    }
    expect(capped.read('!r0:example.org'), isNull);
    expect(capped.read('!r4:example.org'), isNull);
    expect(capped.read('!r5:example.org')?.text, 'x5');
    expect(capped.read('!r54:example.org')?.text, 'x54');
  });

  test('importLegacy never overwrites a draft that exists', () async {
    expect(await store.importLegacy(room, 'old'), isTrue);
    expect(store.read(room)?.text, 'old');
    expect(await store.importLegacy(room, 'older'), isTrue);
    expect(store.read(room)?.text, 'old');
  });
}
