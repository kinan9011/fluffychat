// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/search/index_policy.dart';
import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/message_index.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/fake_search_database.dart';

const _room = '!a:example.org';
const _alice = '@alice:example.org';

IndexedMessage msg(
  int n, {
  String room = _room,
  String sender = _alice,
  int? ts,
  String text = 'hello',
  SearchKind kind = SearchKind.text,
}) => IndexedMessage(
  roomId: room,
  eventId: '\$e$n:example.org',
  senderId: sender,
  timestamp: ts ?? 1700000000000 + n,
  kind: kind,
  text: text,
);

MessageIndex index(
  FakeSearchDatabase db, {
  bool canPersist = true,
  Duration delay = Duration.zero,
  RetentionPolicy? Function(String roomId)? retentionOf,
  DateTime Function()? now,
}) => MessageIndex.forTesting(
  () => db,
  canPersist: () => canPersist,
  persistDelay: delay,
  retentionOf: retentionOf,
  now: now,
);

Map<String, Object?> doc(List<Object?> rows) => {'v': 1, 'e': rows};

List<Object?> row(int n, {Object? text = 'hello', Object? kind = 0}) => [
  _room,
  '\$e$n:example.org',
  _alice,
  1700000000000 + n,
  kind,
  0,
  text,
];

void main() {
  late FakeSearchDatabase db;

  setUp(() {
    db = FakeSearchDatabase();
    Logs().outputEvents.clear();
  });

  group('entries', () {
    test('add keeps one entry per message and replaces the text', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'one'));
      i.add(msg(1, text: 'changed'));
      expect(i.length, 1);
      expect(i.snapshot().single.text, 'changed');
    });

    test('at most 5000 entries: the oldest go first', () async {
      final i = index(db);
      await i.ready;
      for (var n = 0; n < MessageIndex.maxEntries + 3; n++) {
        i.add(msg(n));
      }
      expect(i.length, MessageIndex.maxEntries);
      final ids = i.snapshot().map((e) => e.eventId).toSet();
      expect(ids.contains(r'$e0:example.org'), isFalse);
      expect(ids.contains(r'$e2:example.org'), isFalse);
      expect(ids.contains(r'$e3:example.org'), isTrue);
    });

    test('remove and removeRoom', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1));
      i.add(msg(2));
      i.add(msg(3, room: '!b:example.org'));
      i.remove(_room, r'$e1:example.org');
      expect(i.length, 2);
      i.removeRoom(_room);
      expect(i.snapshot().single.roomId, '!b:example.org');
    });
  });

  group('edits', () {
    test('the author can change the text', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'old'));
      i.applyEdit(
        roomId: _room,
        targetId: r'$e1:example.org',
        editorId: _alice,
        newText: 'see https://example.org',
        at: 10,
      );
      final entry = i.snapshot().single;
      expect(entry.text, 'see https://example.org');
      expect(entry.hasLink, isTrue);
    });

    test('someone else cannot rewrite a message', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'old'));
      i.applyEdit(
        roomId: _room,
        targetId: r'$e1:example.org',
        editorId: '@mallory:example.org',
        newText: 'injected',
        at: 10,
      );
      expect(i.snapshot().single.text, 'old');
    });

    test('an edit of an unknown message is ignored', () async {
      final i = index(db);
      await i.ready;
      i.applyEdit(
        roomId: _room,
        targetId: r'$nope:example.org',
        editorId: _alice,
        newText: 'x',
        at: 10,
      );
      expect(i.length, 0);
    });
  });

  group('edits in any order', () {
    void edit(MessageIndex i, int n, String text, int at, {String? by}) =>
        i.applyEdit(
          roomId: _room,
          targetId: '\$e$n:example.org',
          editorId: by ?? _alice,
          newText: text,
          at: at,
        );

    test(
      'an edit that comes before its message is applied when it comes',
      () async {
        final i = index(db);
        await i.ready;
        edit(i, 1, 'new', 20);
        expect(i.length, 0);
        i.add(msg(1, text: 'old'));
        expect(i.snapshot().single.text, 'new');
      },
    );

    test('the newest edit wins whatever the order they arrive in', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'v0'));
      edit(i, 1, 'v2', 30);
      edit(i, 1, 'v1', 20);
      expect(i.snapshot().single.text, 'v2');
    });

    test('of two early edits the newer one is kept', () async {
      final i = index(db);
      await i.ready;
      edit(i, 1, 'v2', 30);
      edit(i, 1, 'v1', 20);
      i.add(msg(1, text: 'v0'));
      expect(i.snapshot().single.text, 'v2');
    });

    test('the same message arriving again does not undo an edit', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'v0'));
      edit(i, 1, 'v1', 20);
      i.add(msg(1, text: 'v0'));
      expect(i.snapshot().single.text, 'v1');
    });

    test('an early edit by someone else never rewrites the message', () async {
      final i = index(db);
      await i.ready;
      edit(i, 1, 'injected', 20, by: '@mallory:example.org');
      i.add(msg(1, text: 'old'));
      expect(i.snapshot().single.text, 'old');
    });

    test('a redaction drops an early edit', () async {
      final i = index(db);
      await i.ready;
      edit(i, 1, 'new', 20);
      i.remove(_room, r'$e1:example.org');
      i.add(msg(1, text: 'old'));
      expect(i.snapshot().single.text, 'old');
    });

    test('leaving the room and a wipe drop early edits', () async {
      final i = index(db);
      await i.ready;
      edit(i, 1, 'new', 20);
      i.removeRoom(_room);
      i.add(msg(1, text: 'old'));
      expect(i.snapshot().single.text, 'old');
      edit(i, 2, 'new', 20);
      await i.wipe();
      i.add(msg(2, text: 'old'));
      expect(i.snapshot().single.text, 'old');
    });

    test('only a few early edits are kept', () async {
      final i = index(db);
      await i.ready;
      for (var n = 1; n <= MessageIndex.maxPendingEdits + 5; n++) {
        edit(i, n, 'new', 20);
      }
      i.add(msg(1, text: 'old'));
      i.add(msg(MessageIndex.maxPendingEdits + 5, text: 'old'));
      final texts = {for (final e in i.snapshot()) e.eventId: e.text};
      expect(texts[r'$e1:example.org'], 'old');
      expect(
        texts['\$e${MessageIndex.maxPendingEdits + 5}:example.org'],
        'new',
      );
    });
  });

  group('retention', () {
    const day = Duration(days: 1);
    final now = DateTime.fromMillisecondsSinceEpoch(1800000000000);

    test('pruneRetention drops what the timer hides, keeps the rest', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, ts: now.subtract(day * 2).millisecondsSinceEpoch));
      i.add(
        msg(
          2,
          ts: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        ),
      );
      i.add(msg(3, room: '!b:example.org', ts: 1));
      final dropped = i.pruneRetention(
        (roomId) => roomId == _room ? const RetentionPolicy(day) : null,
        now,
      );
      expect(dropped, 1);
      expect(i.snapshot().map((e) => e.eventId).toSet(), {
        r'$e2:example.org',
        r'$e3:example.org',
      });
    });

    List<Object?> storedRows() =>
        db.stored[MessageIndex.documentKey]!['e']! as List<Object?>;

    List<Object?> rowAt(int n, DateTime at) => [
      _room,
      '\$e$n:example.org',
      _alice,
      at.millisecondsSinceEpoch,
      0,
      0,
      'plain words $n',
    ];

    test('an expired row of the stored document is dropped on load and the '
        'document is rewritten without it', () async {
      db.stored[MessageIndex.documentKey] = doc([
        rowAt(1, now.subtract(day * 2)),
        rowAt(2, now.subtract(const Duration(hours: 1))),
      ]);
      final i = index(
        db,
        retentionOf: (_) => const RetentionPolicy(day),
        now: () => now,
      );
      await i.ready;
      expect(i.snapshot().map((e) => e.eventId), [r'$e2:example.org']);
      await i.flush();
      expect(storedRows().map((r) => (r! as List)[1]), [r'$e2:example.org']);
      expect(jsonEncode(db.stored), isNot(contains('plain words 1')));
    });

    test(
      'an entry that expired while it was in memory is not written',
      () async {
        var clock = now.subtract(day * 3);
        final i = index(
          db,
          retentionOf: (_) => const RetentionPolicy(day),
          now: () => clock,
        );
        await i.ready;
        i.add(msg(1, ts: now.subtract(day * 2).millisecondsSinceEpoch));
        i.add(
          msg(
            2,
            ts: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
        );
        clock = now;
        await i.flush();
        expect(storedRows().map((r) => (r! as List)[1]), [r'$e2:example.org']);
        expect(i.length, 1);
      },
    );

    test('rooms without a timer keep everything on load and write', () async {
      db.stored[MessageIndex.documentKey] = doc([
        rowAt(1, now.subtract(day * 400)),
      ]);
      final i = index(db, retentionOf: (_) => null, now: () => now);
      await i.ready;
      i.add(msg(2, ts: 5));
      await i.flush();
      expect(storedRows(), hasLength(2));
    });

    test('polls are hidden by the poll start type', () async {
      final i = index(db);
      await i.ready;
      i.add(
        msg(
          1,
          kind: SearchKind.poll,
          ts: now.subtract(day * 2).millisecondsSinceEpoch,
        ),
      );
      i.pruneRetention((_) => const RetentionPolicy(day), now);
      expect(i.length, 0);
    });
  });

  group('storage', () {
    test(
      'entries are written after the delay, as a versioned document',
      () async {
        final i = index(db);
        await i.ready;
        i.add(msg(1, text: 'secret words'));
        await i.flush();
        final stored = db.stored[MessageIndex.documentKey]!;
        expect(stored['v'], 1);
        expect((stored['e'] as List).single[6], 'secret words');
      },
    );

    test('nothing is written before the delay is over', () async {
      final i = index(db, delay: const Duration(hours: 1));
      await i.ready;
      i.add(msg(1));
      await Future<void>.delayed(Duration.zero);
      expect(db.writes, 0);
      await i.flush();
      expect(db.writes, 1);
    });

    test('many adds are written once', () async {
      final i = index(db);
      await i.ready;
      for (var n = 0; n < 20; n++) {
        i.add(msg(n));
      }
      await i.flush();
      expect(db.writes, 1);
    });

    test('a new index loads what an old one stored', () async {
      final a = index(db);
      await a.ready;
      a.add(msg(1, text: 'kept'));
      await a.flush();
      final b = index(db);
      await b.ready;
      expect(b.snapshot().single.text, 'kept');
    });

    test('the document is cut to 2 MiB, oldest rows first', () async {
      final i = index(db);
      await i.ready;
      final text = 'x' * 500;
      for (var n = 0; n < 4000; n++) {
        i.add(msg(n, text: text));
      }
      await i.flush();
      final stored = db.stored[MessageIndex.documentKey]!;
      expect(
        utf8.encode(jsonEncode(stored)).length,
        lessThanOrEqualTo(MessageIndex.maxDocumentBytes),
      );
      final rows = (stored['e'] as List).cast<List<Object?>>();
      expect(rows.length, lessThan(4000));
      expect(rows.first[1], r'$e3999:example.org');
      expect(i.length, rows.length);
    });

    test(
      'where the database is not encrypted nothing is read or written',
      () async {
        final i = index(db, canPersist: false);
        await i.ready;
        i.add(msg(1));
        await i.flush();
        expect(db.reads, 0);
        expect(db.writes, 0);
        expect(i.persistent, isFalse);
        expect(i.length, 1);
      },
    );

    test('a failing database never throws and keeps memory', () async {
      db.failWrites = true;
      final i = index(db);
      await i.ready;
      i.add(msg(1));
      await i.flush();
      expect(i.length, 1);
      db.failWrites = false;
      await i.flush();
      expect(db.stored, isNotEmpty);
    });

    test('an unreadable document is never overwritten', () async {
      db.stored[MessageIndex.documentKey] = doc([row(1, text: 'precious')]);
      db.failReads = true;
      final i = index(db);
      await i.ready;
      i.add(msg(2));
      await i.flush();
      expect(
        (db.stored[MessageIndex.documentKey]!['e'] as List).single[6],
        'precious',
      );
      db.failReads = false;
      await i.flush();
      final rows = db.stored[MessageIndex.documentKey]!['e'] as List;
      expect(rows.length, 2);
    });

    test('logs never contain message text or ids', () async {
      db.failWrites = true;
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'SENTINEL-SECRET-BODY'));
      await i.flush();
      final output = Logs().outputEvents
          .map((e) => '${e.title} ${e.exception} ${e.stackTrace}')
          .join('\n');
      expect(output, isNot(contains('SENTINEL-SECRET-BODY')));
      expect(output, isNot(contains(r'$e1:example.org')));
      expect(output, isNot(contains(_room)));
    });
  });

  group('document parsing', () {
    test('rows that do not look like ours are dropped', () {
      final good = row(1);
      final parsed = MessageIndex.parse(
        doc([
          good,
          'x',
          5,
          null,
          <Object?>[],
          [..._row(2), 'extra'],
          row(3, kind: 99),
          row(4, kind: -1),
          row(5, kind: 'text'),
          row(6, text: 5),
          row(7, text: ''),
          ['bad room', '\$e8:example.org', _alice, 1, 0, 0, 'x'],
          [_room, 'no-dollar', _alice, 1, 0, 0, 'x'],
          [_room, '\$e9:example.org', 'alice', 1, 0, 0, 'x'],
          [_room, '\$e10:example.org', _alice, 'now', 0, 0, 'x'],
          [_room, '\$e11:example.org', _alice, -4, 0, 0, 'x'],
          [_room, '\$e12:example.org', _alice, 1, 0, 9, 'x'],
        ]),
      );
      expect(parsed.map((e) => e.eventId), [r'$e1:example.org']);
    });

    test('a wrong version, a wrong shape or no document gives nothing', () {
      expect(
        MessageIndex.parse({
          'v': 2,
          'e': [row(1)],
        }),
        isEmpty,
      );
      expect(MessageIndex.parse({'v': 1, 'e': 'x'}), isEmpty);
      expect(
        MessageIndex.parse({
          'e': [row(1)],
        }),
        isEmpty,
      );
      expect(MessageIndex.parse('x'), isEmpty);
      expect(MessageIndex.parse(null), isEmpty);
    });

    test('20000 rows give the newest 5000', () {
      final rows = [for (var n = 1; n <= 20000; n++) row(n)];
      final parsed = MessageIndex.parse(doc(rows));
      expect(parsed.length, MessageIndex.maxEntries);
      expect(
        parsed.map((e) => e.timestamp).reduce((a, b) => a < b ? a : b),
        1700000000000 + 15001,
      );
    });

    test('text from the database is cut to 500 characters', () {
      final parsed = MessageIndex.parse(doc([row(1, text: 'a' * 10000000)]));
      expect(parsed.single.text.length, IndexPolicy.maxTextChars);
    });

    test('flags and kind survive a round trip', () async {
      final i = index(db);
      await i.ready;
      i.add(
        IndexedMessage(
          roomId: _room,
          eventId: r'$e1:example.org',
          senderId: _alice,
          timestamp: 1700000000001,
          kind: SearchKind.voice,
          text: 'x',
          mentionsMe: true,
          hasLink: true,
        ),
      );
      await i.flush();
      final b = index(db);
      await b.ready;
      final entry = b.snapshot().single;
      expect(entry.kind, SearchKind.voice);
      expect(entry.mentionsMe, isTrue);
      expect(entry.hasLink, isTrue);
    });
  });

  group('wipe', () {
    test('forgets memory and writes an empty document', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'secret'));
      await i.flush();
      await i.wipe();
      expect(i.length, 0);
      expect(db.stored[MessageIndex.documentKey], {'v': 1, 'e': <Object?>[]});
    });

    test('nothing of the old text stays in the stored document', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1, text: 'SENTINEL-SECRET-BODY'));
      await i.flush();
      await i.wipe();
      expect(jsonEncode(db.stored), isNot(contains('SENTINEL-SECRET-BODY')));
    });

    test(
      'a write that is in flight cannot bring the old document back',
      () async {
        final i = index(db);
        await i.ready;
        i.add(msg(1, text: 'secret'));
        final gate = Completer<void>();
        db.writeGate = gate;
        final flushed = i.flush();
        await Future<void>.delayed(Duration.zero);
        final wiped = i.wipe();
        gate.complete();
        await flushed;
        await wiped;
        expect(db.stored[MessageIndex.documentKey], {'v': 1, 'e': <Object?>[]});
      },
    );

    test('a load that is in flight cannot bring rows back', () async {
      db.stored[MessageIndex.documentKey] = doc([row(1)]);
      db.readGate = Completer<void>();
      final i = index(db);
      await Future<void>.delayed(Duration.zero);
      final wiped = i.wipe();
      db.readGate!.complete();
      await i.ready;
      await wiped;
      expect(i.length, 0);
    });

    test('entries added after a wipe are kept and stored', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1));
      await i.wipe();
      i.add(msg(2, text: 'new'));
      await i.flush();
      expect(i.snapshot().single.text, 'new');
      expect((db.stored[MessageIndex.documentKey]!['e'] as List).length, 1);
    });

    test('wipe completes when the database is closed', () async {
      final i = index(db);
      await i.ready;
      i.add(msg(1));
      db.failWrites = true;
      await i.wipe();
      expect(i.length, 0);
    });

    test(
      'wipe also empties a document written while it was encrypted',
      () async {
        db.stored[MessageIndex.documentKey] = doc([row(1)]);
        final i = index(db, canPersist: false);
        await i.ready;
        await i.wipe();
        expect(db.stored[MessageIndex.documentKey], {'v': 1, 'e': <Object?>[]});
      },
    );

    test('a pending timer does not write after a wipe', () async {
      final i = index(db, delay: const Duration(milliseconds: 20));
      await i.ready;
      i.add(msg(1));
      await i.wipe();
      final writesAfterWipe = db.writes;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(db.writes, writesAfterWipe);
      expect(db.stored[MessageIndex.documentKey], {'v': 1, 'e': <Object?>[]});
    });
  });
}

List<Object?> _row(int n) => row(n);
