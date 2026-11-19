// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/draft_migration.dart';
import 'package:odango/utils/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/test_client.dart';

class _Db implements DatabaseApi {
  _Db(this.inner, {this.staleReads = false, this.failWrites = false});

  final DatabaseApi inner;
  bool staleReads;
  bool failWrites;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) => failWrites
      ? throw StateError('write failed')
      : inner.cacheCustomObject(cacheKey, object);

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) =>
      staleReads ? Future.value(null) : inner.getCustomCacheObject(cacheKey);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Client first;
  late Client second;
  late SharedPreferences prefs;

  Future<void> join(Client client, String id) async {
    client.rooms.add(testChat(client, id));
  }

  Set<String> legacyKeys() =>
      prefs.getKeys().where((k) => k.startsWith('draft_')).toSet();

  setUp(() async {
    first = await prepareTestClient(clientName: 'migration-first');
    second = await prepareTestClient(clientName: 'migration-second');
    await first.database.cacheCustomObject(DraftStore.documentKey, {});
    await second.database.cacheCustomObject(DraftStore.documentKey, {});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test(
    'a draft moves to the client that joined the room and the plaintext goes',
    () async {
      await join(first, '!a:example.org');
      await join(second, '!b:example.org');
      await prefs.setString('draft_!a:example.org', 'for the first');
      await prefs.setString('draft_!b:example.org', 'for the second');
      final moved = await migrateLegacyDrafts(
        prefs: prefs,
        clients: [first, second],
      );
      expect(moved, 2);
      expect(
        DraftStore.of(first).read('!a:example.org')?.text,
        'for the first',
      );
      expect(DraftStore.of(first).read('!b:example.org'), isNull);
      expect(
        DraftStore.of(second).read('!b:example.org')?.text,
        'for the second',
      );
      expect(legacyKeys(), isEmpty);
    },
  );

  test('a draft of a room without a server part moves too', () async {
    final v12 = '!${'Z9_-' * 10}xyz';
    await join(first, v12);
    await prefs.setString('draft_$v12', 'new style room');
    await migrateLegacyDrafts(prefs: prefs, clients: [first, second]);
    expect(DraftStore.of(first).read(v12)?.text, 'new style room');
    expect(legacyKeys(), isEmpty);
  });

  test('a room joined by several accounts goes to the first only', () async {
    await join(first, '!s:example.org');
    await join(second, '!s:example.org');
    await prefs.setString('draft_!s:example.org', 'shared');
    await migrateLegacyDrafts(prefs: prefs, clients: [first, second]);
    expect(DraftStore.of(first).read('!s:example.org')?.text, 'shared');
    expect(DraftStore.of(second).read('!s:example.org'), isNull);
    expect(legacyKeys(), isEmpty);
  });

  test(
    'a draft of a room nobody joined is dropped with its plaintext',
    () async {
      await prefs.setString('draft_!left:example.org', 'stale');
      final moved = await migrateLegacyDrafts(
        prefs: prefs,
        clients: [first, second],
      );
      expect(moved, 0);
      expect(DraftStore.of(first).read('!left:example.org'), isNull);
      expect(DraftStore.of(second).read('!left:example.org'), isNull);
      expect(legacyKeys(), isEmpty);
    },
  );

  test(
    'drafts of an account that has not synced yet survive and move after its first sync',
    () async {
      final fresh = await prepareTestClient(
        clientName: 'migration-fresh',
        waitForFirstSync: false,
      );
      await fresh.database.cacheCustomObject(DraftStore.documentKey, {});
      expect(fresh.prevBatch, isNull);
      await prefs.setString('draft_!late:example.org', 'typed before update');
      final run = migrateLegacyDrafts(prefs: prefs, clients: [fresh]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(legacyKeys(), {'draft_!late:example.org'});
      await join(fresh, '!late:example.org');
      await fresh.oneShotSync();
      expect(await run, 1);
      expect(legacyKeys(), isEmpty);
      expect(
        DraftStore.of(fresh).read('!late:example.org')?.text,
        'typed before update',
      );
    },
  );

  test(
    'garbage entries are removed, valid ones kept, unrelated keys untouched',
    () async {
      await join(first, '!ok:example.org');
      await prefs.setString('draft_!ok:example.org', 'fine');
      await prefs.setInt('draft_!num:example.org', 3);
      await prefs.setString('draft_nonsense', 'x');
      await prefs.setString('draft_!blank:example.org', '  \n ');
      await prefs.setString('theme', 'dark');
      await migrateLegacyDrafts(prefs: prefs, clients: [first]);
      expect(legacyKeys(), isEmpty);
      expect(prefs.getString('theme'), 'dark');
      expect(DraftStore.of(first).read('!ok:example.org')?.text, 'fine');
    },
  );

  test('a huge draft is cut to the cap', () async {
    await join(first, '!big:example.org');
    await prefs.setString('draft_!big:example.org', 'a' * 20000);
    await migrateLegacyDrafts(prefs: prefs, clients: [first]);
    expect(DraftStore.of(first).read('!big:example.org')?.text.length, 8000);
  });

  test('only the first thousand keys are scanned', () async {
    for (var i = 0; i < 1500; i++) {
      await prefs.setString('draft_!r$i:example.org', 'x');
    }
    await migrateLegacyDrafts(prefs: prefs, clients: [first]);
    expect(legacyKeys().length, 500);
  });

  test('running twice is safe and never overwrites a newer draft', () async {
    await join(first, '!twice:example.org');
    await prefs.setString('draft_!twice:example.org', 'old');
    await migrateLegacyDrafts(prefs: prefs, clients: [first]);
    await DraftStore.of(first).write('!twice:example.org', 'newer');
    await prefs.setString('draft_!twice:example.org', 'old again');
    await migrateLegacyDrafts(prefs: prefs, clients: [first]);
    expect(DraftStore.of(first).read('!twice:example.org')?.text, 'newer');
    expect(legacyKeys(), isEmpty);
  });

  test(
    'a failed encrypted write keeps the plaintext for the next start',
    () async {
      await join(first, '!fail:example.org');
      await prefs.setString('draft_!fail:example.org', 'must not be lost');
      final failing = DraftStore.forTesting(
        () => _Db(first.database, failWrites: true),
      );
      final moved = await migrateLegacyDrafts(
        prefs: prefs,
        clients: [first],
        storeOf: (_) => failing,
      );
      expect(moved, 0);
      expect(legacyKeys(), {'draft_!fail:example.org'});
      await migrateLegacyDrafts(prefs: prefs, clients: [first]);
      expect(legacyKeys(), isEmpty);
      expect(
        DraftStore.of(first).read('!fail:example.org')?.text,
        'must not be lost',
      );
    },
  );

  test('the plaintext goes only after the stored copy reads back', () async {
    await join(first, '!stale:example.org');
    await prefs.setString('draft_!stale:example.org', 'verify me');
    final blind = DraftStore.forTesting(
      () => _Db(first.database, staleReads: true),
    );
    await migrateLegacyDrafts(
      prefs: prefs,
      clients: [first],
      storeOf: (_) => blind,
    );
    expect(legacyKeys(), {'draft_!stale:example.org'});
    final moved = await migrateLegacyDrafts(prefs: prefs, clients: [first]);
    expect(moved, 1);
    expect(legacyKeys(), isEmpty);
  });

  test('draft text never reaches the log', () async {
    await join(first, '!log:example.org');
    await prefs.setString('draft_!log:example.org', 'SENTINEL-DRAFT-7f3');
    Logs().outputEvents.clear();
    await migrateLegacyDrafts(prefs: prefs, clients: [first]);
    for (final event in Logs().outputEvents) {
      expect(event.title, isNot(contains('SENTINEL')));
      expect('${event.exception}', isNot(contains('SENTINEL')));
    }
  });
}
