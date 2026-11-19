// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/retention/retention_policy.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/local_search.dart';
import 'package:odango/utils/search/search_filter.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/utils/search/search_query.dart';

void main() {
  final now = DateTime(2031, 6, 15, 12);
  const day = Duration(days: 1);

  IndexedMessage msg(
    int n,
    String text, {
    String room = '!a:example.org',
    DateTime? at,
    SearchKind kind = SearchKind.text,
  }) => IndexedMessage(
    roomId: room,
    eventId: '\$e$n:example.org',
    senderId: '@alice:example.org',
    timestamp:
        (at ?? now.subtract(Duration(minutes: n))).millisecondsSinceEpoch,
    kind: kind,
    text: text,
  );

  List<SearchHit> run(
    List<IndexedMessage> entries,
    String query, {
    MessageSearchFilter filter = MessageSearchFilter.none,
    RetentionPolicy? Function(String)? retention,
    bool Function(String)? visible,
    int limit = 100,
  }) => LocalSearch.run(
    entries,
    SearchQuery.parse(query),
    filter,
    now: now,
    retentionOf: retention ?? (_) => null,
    roomVisible: visible ?? (_) => true,
    limit: limit,
  );

  test('every term has to be in the text (AND)', () {
    final entries = [
      msg(1, 'release notes are ready'),
      msg(2, 'release tomorrow'),
      msg(3, 'notes only'),
    ];
    expect(run(entries, 'release notes').map((h) => h.message.eventId), [
      r'$e1:example.org',
    ]);
  });

  test('terms match in any case and special characters are literal', () {
    final entries = [
      msg(1, 'Release NOTES (draft) a.b'),
      msg(2, 'release notes draft axb'),
    ];
    expect(run(entries, 'notes').length, 2);
    expect(run(entries, '(draft) a.b').map((h) => h.message.eventId), [
      r'$e1:example.org',
    ]);
    expect(run(entries, '.*'), isEmpty);
  });

  test('highlights point into the original text', () {
    final hit = run([msg(1, 'See The RELEASE now')], 'release').single;
    expect(hit.highlights, [(start: 8, end: 15)]);
  });

  test('newest first and limited', () {
    final entries = [for (var n = 1; n <= 10; n++) msg(n, 'word $n')];
    final hits = run(entries, 'word', limit: 3);
    expect(hits.map((h) => h.message.eventId), [
      r'$e1:example.org',
      r'$e2:example.org',
      r'$e3:example.org',
    ]);
  });

  test('empty query with an empty filter finds nothing', () {
    expect(run([msg(1, 'x')], ''), isEmpty);
  });

  test('an empty query with a filter lists what the filter matches', () {
    final entries = [msg(1, 'a.pdf', kind: SearchKind.file), msg(2, 'hello')];
    final hits = run(
      entries,
      '',
      filter: const MessageSearchFilter().copyWith(types: {SearchType.files}),
    );
    expect(hits.single.message.eventId, r'$e1:example.org');
    expect(hits.single.highlights, isEmpty);
  });

  test('rooms that are not visible any more are dropped', () {
    final entries = [
      msg(1, 'needle', room: '!gone:example.org'),
      msg(2, 'needle'),
    ];
    final hits = run(
      entries,
      'needle',
      visible: (id) => id != '!gone:example.org',
    );
    expect(hits.single.message.eventId, r'$e2:example.org');
  });

  group('retention', () {
    test('hidden messages are never returned, the boundary included', () {
      final entries = [
        msg(1, 'needle', at: now.subtract(day)),
        msg(
          2,
          'needle',
          at: now.subtract(day).add(const Duration(milliseconds: 1)),
        ),
        msg(3, 'needle', at: now.subtract(day * 5)),
      ];
      final hits = run(
        entries,
        'needle',
        retention: (_) => const RetentionPolicy(day),
      );
      expect(hits.map((h) => h.message.eventId), [r'$e2:example.org']);
    });

    test('only the room with a timer is affected', () {
      final entries = [
        msg(1, 'needle', at: now.subtract(day * 5)),
        msg(2, 'needle', room: '!b:example.org', at: now.subtract(day * 5)),
      ];
      final hits = run(
        entries,
        'needle',
        retention: (id) =>
            id == '!a:example.org' ? const RetentionPolicy(day) : null,
      );
      expect(hits.single.message.roomId, '!b:example.org');
    });

    test('a policy that does not expire on clients hides nothing', () {
      final policy = RetentionPolicy.fromContent({
        'max_lifetime': day.inMilliseconds,
      });
      expect(policy, isNull);
      final hits = run(
        [msg(1, 'needle', at: now.subtract(day * 5))],
        'needle',
        retention: (_) => policy,
      );
      expect(hits, hasLength(1));
    });

    test('hidden polls are dropped too', () {
      final hits = run(
        [msg(1, 'lunch?', kind: SearchKind.poll, at: now.subtract(day * 5))],
        'lunch',
        retention: (_) => const RetentionPolicy(day),
      );
      expect(hits, isEmpty);
    });

    test('the filter does not bring a hidden message back', () {
      final hits = run(
        [msg(1, 'a.pdf', kind: SearchKind.file, at: now.subtract(day * 5))],
        '',
        filter: const MessageSearchFilter().copyWith(types: {SearchType.files}),
        retention: (_) => const RetentionPolicy(day),
      );
      expect(hits, isEmpty);
    });
  });

  group('highlights', () {
    SearchQuery q(String s) => SearchQuery.parse(s);

    test('the first occurrence of each term', () {
      expect(
        LocalSearch.highlights('see the release notes', q('notes release')),
        [(start: 8, end: 15), (start: 16, end: 21)],
      );
    });

    test('a term at the very end', () {
      expect(LocalSearch.highlights('abc end', q('end')), [(start: 4, end: 7)]);
    });

    test('overlapping terms are merged', () {
      expect(LocalSearch.highlights('foobar', q('foob obar')), [
        (start: 0, end: 6),
      ]);
    });

    test('a term that is contained in another is merged', () {
      expect(LocalSearch.highlights('foobar', q('foobar bar')), [
        (start: 0, end: 6),
      ]);
    });
  });
}
