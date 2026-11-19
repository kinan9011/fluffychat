// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/search/search_filter.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/utils/search/search_query.dart';
import 'package:odango/utils/search/server_search.dart';

import 'utils/recording_api.dart';
import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room open;
  late Room open2;
  late Room secret;
  final api = RecordingApi();
  final now = DateTime(2031, 6, 15, 12);
  final calls = <(Categories, String?)>[];
  var answer = <String, Object?>{};

  Map<String, Object?> response(
    List<Map<String, Object?>> events, {
    Object? nextBatch,
  }) => {
    'search_categories': {
      'room_events': {
        'count': events.length,
        'next_batch': ?nextBatch,
        'results': [
          for (final event in events) {'rank': 1.0, 'result': event},
        ],
      },
    },
  };

  Map<String, Object?> event(
    String roomId,
    int n, {
    String body = 'needle here',
    Object? sender = '@alice:example.org',
    String type = 'm.room.message',
    String msgtype = 'm.text',
    DateTime? at,
    Map<String, Object?> extra = const {},
  }) => {
    'event_id': '\$e$n:example.org',
    'room_id': roomId,
    'sender': sender,
    'type': type,
    'origin_server_ts':
        (at ?? now.subtract(const Duration(hours: 1))).millisecondsSinceEpoch,
    'content': {'msgtype': msgtype, 'body': body, ...extra},
  };

  setUpAll(() async {
    client = await prepareTestClient(httpClient: api);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  setUp(() {
    client.rooms.clear();
    open = searchRoom(client, '!open:example.org', encrypted: false);
    open2 = searchRoom(client, '!open2:example.org', encrypted: false);
    secret = searchRoom(client, '!secret:example.org');
    client.rooms.addAll([open, open2, secret]);
    calls.clear();
    answer = response([]);
    api.clear();
  });

  ServerSearch server() => ServerSearch(
    client,
    now: () => now,
    api: (categories, {nextBatch}) async {
      calls.add((categories, nextBatch));
      return SearchResults.fromJson(answer);
    },
  );

  SearchQuery q(String text) => SearchQuery.parse(text);

  Map<String, Object?> sentCriteria() =>
      calls.single.$1.toJson()['room_events']! as Map<String, Object?>;

  group('what is sent', () {
    test('no request without a search word', () async {
      final page = await server().search(q('  '), MessageSearchFilter.none);
      expect(page.hits, isEmpty);
      expect(calls, isEmpty);
    });

    test('no request when every room is encrypted', () async {
      client.rooms
        ..clear()
        ..add(secret);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.hits, isEmpty);
      expect(calls, isEmpty);
    });

    test('only joined, unencrypted rooms are searched', () async {
      client.rooms.addAll([
        searchRoom(
          client,
          '!invited:example.org',
          encrypted: false,
          membership: Membership.invite,
        ),
        searchRoom(
          client,
          '!left:example.org',
          encrypted: false,
          membership: Membership.leave,
        ),
      ]);
      await server().search(q('needle'), MessageSearchFilter.none);
      final filter = sentCriteria()['filter']! as Map<String, Object?>;
      expect((filter['rooms']! as List).toSet(), {
        '!open:example.org',
        '!open2:example.org',
      });
      expect(filter['limit'], 20);
    });

    test(
      'the search word is the normalised query, in the message body',
      () async {
        await server().search(q('  Needle   Two '), MessageSearchFilter.none);
        final criteria = sentCriteria();
        expect(criteria['search_term'], 'needle two');
        expect(criteria['keys'], ['content.body']);
        expect(criteria['order_by'], 'recent');
        expect(criteria.containsKey('event_context'), isFalse);
        expect(criteria.containsKey('include_state'), isFalse);
        expect(criteria.containsKey('groupings'), isFalse);
      },
    );

    test('the in-filter narrows the rooms, senders are passed on', () async {
      final filter = const MessageSearchFilter().copyWith(
        inRoomIds: {'!open2:example.org', '!secret:example.org'},
        fromIds: {'@bob:example.org'},
      );
      await server().search(q('needle'), filter);
      final sent = sentCriteria()['filter']! as Map<String, Object?>;
      expect(sent['rooms'], ['!open2:example.org']);
      expect(sent['senders'], ['@bob:example.org']);
    });

    test('an in-filter with only encrypted rooms sends nothing', () async {
      final filter = const MessageSearchFilter().copyWith(
        inRoomIds: {'!secret:example.org'},
      );
      await server().search(q('needle'), filter);
      expect(calls, isEmpty);
    });

    test('media types ask the server for messages with a file', () async {
      await server().search(
        q('needle'),
        const MessageSearchFilter().copyWith(types: {SearchType.files}),
      );
      expect((sentCriteria()['filter']! as Map)['contains_url'], isTrue);
    });

    test('links and mixed types do not', () async {
      await server().search(
        q('needle'),
        const MessageSearchFilter().copyWith(
          types: {SearchType.files, SearchType.links},
        ),
      );
      expect(
        (sentCriteria()['filter']! as Map).containsKey('contains_url'),
        isFalse,
      );
    });

    test('at most 200 rooms, the most recently active first', () async {
      client.rooms.clear();
      for (var n = 0; n < 250; n++) {
        client.rooms.add(
          searchRoom(client, '!r$n:example.org', encrypted: false),
        );
      }
      await server().search(q('needle'), MessageSearchFilter.none);
      expect(
        ((sentCriteria()['filter']! as Map)['rooms']! as List).length,
        200,
      );
    });

    test('the page cap is five pages', () async {
      final page = await server().search(
        q('needle'),
        MessageSearchFilter.none,
        page: ServerSearch.maxPages,
      );
      expect(page.hits, isEmpty);
      expect(calls, isEmpty);
    });

    test('the next batch token is passed back', () async {
      await server().search(
        q('needle'),
        MessageSearchFilter.none,
        nextBatch: 'tok',
      );
      expect(calls.single.$2, 'tok');
    });
  });

  group('what comes back', () {
    test('a plain message is a hit with highlights', () async {
      answer = response([
        event('!open:example.org', 1, body: 'The Needle here'),
      ]);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      final hit = page.hits.single;
      expect(hit.message.roomId, '!open:example.org');
      expect(hit.message.text, 'The Needle here');
      expect(hit.highlights, [(start: 4, end: 10)]);
    });

    test('events of rooms that were not asked for are dropped', () async {
      answer = response([
        event('!foreign:example.org', 1),
        event('!open:example.org', 2),
      ]);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.hits.map((h) => h.message.roomId), ['!open:example.org']);
    });

    test('a joined room that was not part of the request is dropped', () async {
      answer = response([
        event('!open2:example.org', 1),
        event('!open:example.org', 2),
      ]);
      final filter = const MessageSearchFilter().copyWith(
        inRoomIds: {'!open:example.org'},
      );
      final page = await server().search(q('needle'), filter);
      expect(page.hits.map((h) => h.message.roomId), ['!open:example.org']);
    });

    test(
      'a joined room beyond the 200 that were asked for is dropped',
      () async {
        client.rooms.clear();
        for (var n = 0; n < 250; n++) {
          client.rooms.add(
            searchRoom(client, '!r$n:example.org', encrypted: false),
          );
        }
        final asked = server().eligibleRooms().map((room) => room.id).toSet();
        final outsider = client.rooms.firstWhere(
          (room) => !asked.contains(room.id),
        );
        answer = response([event(outsider.id, 1)]);
        final page = await server().search(
          q('needle'),
          MessageSearchFilter.none,
        );
        expect(page.hits, isEmpty);
      },
    );

    test(
      'events of encrypted rooms are dropped even if the server sends them',
      () async {
        answer = response([event('!secret:example.org', 1)]);
        final page = await server().search(
          q('needle'),
          MessageSearchFilter.none,
        );
        expect(page.hits, isEmpty);
      },
    );

    test('a room that was left meanwhile is dropped', () async {
      answer = response([event('!open:example.org', 1)]);
      final s = ServerSearch(
        client,
        now: () => now,
        api: (categories, {nextBatch}) async {
          open.membership = Membership.leave;
          return SearchResults.fromJson(answer);
        },
      );
      final page = await s.search(q('needle'), MessageSearchFilter.none);
      expect(page.hits, isEmpty);
    });

    test('a room that became encrypted meanwhile is dropped', () async {
      answer = response([event('!open:example.org', 1)]);
      final s = ServerSearch(
        client,
        now: () => now,
        api: (categories, {nextBatch}) async {
          open.setState(
            Event(
              type: EventTypes.Encryption,
              stateKey: '',
              content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
              room: open,
              eventId: r'$enc:example.org',
              senderId: '@alice:example.org',
              originServerTs: DateTime(2025),
            ),
          );
          return SearchResults.fromJson(answer);
        },
      );
      final page = await s.search(q('needle'), MessageSearchFilter.none);
      expect(page.hits, isEmpty);
    });

    test('bad ids, other types and malformed bodies are dropped', () async {
      answer = response([
        {...event('!open:example.org', 1), 'event_id': 'no-dollar'},
        event('!open:example.org', 2, sender: 'alice'),
        event('!open:example.org', 3, type: 'm.room.topic'),
        event('!open:example.org', 4, msgtype: 'm.location'),
        {
          ...event('!open:example.org', 5),
          'content': {'msgtype': 'm.text', 'body': 5},
        },
        event('!open:example.org', 6, body: 'needle ok'),
      ]);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.hits.map((h) => h.message.eventId), [r'$e6:example.org']);
    });

    test('a page is cut at 20 hits', () async {
      answer = response([
        for (var n = 1; n <= 500; n++) event('!open:example.org', n),
      ]);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.hits.length, ServerSearch.pageSize);
    });

    test('a next batch token over 512 characters ends the paging', () async {
      answer = response([], nextBatch: 'x' * 1000000);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.nextBatch, isNull);
      answer = response([], nextBatch: 'x' * 512);
      final ok = await server().search(q('needle'), MessageSearchFilter.none);
      expect(ok.nextBatch, 'x' * 512);
      answer = response([], nextBatch: '');
      final empty = await server().search(
        q('needle'),
        MessageSearchFilter.none,
      );
      expect(empty.nextBatch, isNull);
    });

    test('the client side filter is applied to what comes back', () async {
      answer = response([
        event('!open:example.org', 1, sender: '@bob:example.org'),
        event('!open:example.org', 2),
      ]);
      final filter = const MessageSearchFilter().copyWith(
        fromIds: {'@alice:example.org'},
      );
      final page = await server().search(q('needle'), filter);
      expect(page.hits.map((h) => h.message.eventId), [r'$e2:example.org']);
    });

    test('type and date filters are applied too', () async {
      answer = response([
        event('!open:example.org', 1, msgtype: 'm.file', body: 'needle.pdf'),
        event('!open:example.org', 2),
        event(
          '!open:example.org',
          3,
          msgtype: 'm.file',
          body: 'needle.old',
          at: now.subtract(const Duration(days: 40)),
        ),
      ]);
      final filter = const MessageSearchFilter().copyWith(
        types: {SearchType.files},
        date: DatePreset.month,
      );
      final page = await server().search(q('needle'), filter);
      expect(page.hits.map((h) => h.message.eventId), [r'$e1:example.org']);
    });

    test('messages hidden by the retention timer are dropped', () async {
      open.setState(
        Event(
          type: 'm.room.retention',
          stateKey: '',
          content: {
            'max_lifetime': const Duration(days: 1).inMilliseconds,
            'expire_on_clients': true,
          },
          room: open,
          eventId: r'$ret:example.org',
          senderId: '@alice:example.org',
          originServerTs: DateTime(2025),
        ),
      );
      answer = response([
        event(
          '!open:example.org',
          1,
          at: now.subtract(const Duration(days: 3)),
        ),
        event(
          '!open:example.org',
          2,
          at: now.subtract(const Duration(hours: 2)),
        ),
        event(
          '!open2:example.org',
          3,
          at: now.subtract(const Duration(days: 3)),
        ),
      ]);
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.hits.map((h) => h.message.eventId), [
        r'$e2:example.org',
        r'$e3:example.org',
      ]);
    });

    test('a response that does not parse is an error for the caller', () async {
      answer = {'search_categories': 'x'};
      await expectLater(
        server().search(q('needle'), MessageSearchFilter.none),
        throwsA(anything),
      );
    });

    test('an empty response is an empty page', () async {
      answer = {'search_categories': <String, Object?>{}};
      final page = await server().search(q('needle'), MessageSearchFilter.none);
      expect(page.hits, isEmpty);
      expect(page.nextBatch, isNull);
    });
  });

  test(
    'the default api goes to the own homeserver search endpoint only',
    () async {
      final real = ServerSearch(client, now: () => now);
      await real.search(q('needle'), MessageSearchFilter.none);
      final posts = api.requests('/search', method: 'POST');
      expect(posts, hasLength(1));
      expect(posts.single.url.host, client.homeserver!.host);
      expect(api.log.where((r) => r.path.contains('/search')), hasLength(1));
    },
  );
}
