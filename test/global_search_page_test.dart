// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/global_search/global_search.dart';
import 'package:fluffychat/pages/global_search/global_search_view.dart';
import 'package:fluffychat/pages/global_search/search_filter_sheet.dart';
import 'package:fluffychat/pages/global_search/search_result_widgets.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/search/index_feeder.dart';
import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/message_index.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/utils/search/server_search.dart';
import 'package:fluffychat/utils/search/unencrypted_scan.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';
import 'utils/search_fixtures.dart';

const _secretRoom = '!secret:example.org';
const _openRoom = '!open:example.org';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  var searchHandler = (Object? body) => <String, Object?>{};

  Map<String, Object?> emptySearch(Object? body) => {
    'search_categories': {
      'room_events': {'count': 0, 'results': <Object?>[]},
    },
  };

  setUpAll(harness.setUpAll);

  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.onRequest = null;
    unencryptedClientsThisSession.clear();
    searchHandler = emptySearch;
    api.api['POST']!['/client/v3/search'] = (req) => searchHandler(req);
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': <Object?>[],
      'limited': false,
    };
    api.api['POST']!['/client/v3/publicRooms'] = (_) => {
      'chunk': <Object?>[],
      'total_room_count_estimate': 0,
    };
    final client = harness.client;
    harness.resetRooms();
    MessageIndex.forget(client);
    await client.database.cacheCustomObject(MessageIndex.documentKey, {
      'v': 1,
      'e': <Object?>[],
    });
  });
  tearDown(harness.tearDown);

  Map<String, Object?> hits(List<Map<String, Object?>> events) => {
    'search_categories': {
      'room_events': {
        'count': events.length,
        'results': [
          for (final event in events) {'rank': 1.0, 'result': event},
        ],
      },
    },
  };

  Map<String, Object?> serverEvent(String roomId, int n, String body) => {
    'event_id': '\$srv$n:example.org',
    'room_id': roomId,
    'sender': '@alice:example.org',
    'type': 'm.room.message',
    'origin_server_ts': DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch,
    'content': {'msgtype': 'm.text', 'body': body},
  };

  Room addRoom(String id, String name, {bool encrypted = true}) {
    final room = searchRoom(harness.client, id, encrypted: encrypted);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': name},
        room: room,
        eventId: '\$name$id',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    harness.client.rooms.add(room);
    return room;
  }

  IndexedMessage indexed(String roomId, int n, String text) => IndexedMessage(
    roomId: roomId,
    eventId: '\$idx$n:example.org',
    senderId: '@alice:example.org',
    timestamp: DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch,
    kind: SearchKind.text,
    text: text,
  );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(GlobalSearchView.fieldKey), text);
    await tester.pump(const Duration(milliseconds: 350));
    await harness.settle(tester, rounds: 3);
  }

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(GlobalSearch)));

  String location() =>
      FluffyChatApp.router.routeInformationProvider.value.uri.toString();

  bool sentQuery(String word) => api.log.any(
    (r) =>
        r.method == 'POST' &&
        (r.path.endsWith('/search') ||
            r.path.endsWith('/user_directory/search') ||
            r.path.endsWith('/publicRooms')) &&
        r.body.contains(word),
  );

  group('what is shown', () {
    testWidgets('chats match at once, before any request', (tester) async {
      addRoom(_secretRoom, 'Secret book club');
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      api.clear();
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'book');
      await tester.pump();
      expect(find.text('Secret book club'), findsOneWidget);
      expect(find.text('Open air'), findsNothing);
      expect(api.requests('/search', method: 'POST'), isEmpty);
      await tester.pump(const Duration(milliseconds: 350));
      await harness.finish(tester);
    });

    testWidgets('an indexed message of an encrypted chat is a hit', (
      tester,
    ) async {
      addRoom(_secretRoom, 'Secret book club');
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      index.add(indexed(_secretRoom, 1, 'the Release notes are ready'));
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'release');
      expect(
        find.textContaining('Release notes', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Secret book club'), findsWidgets);
      await harness.finish(tester);
    });

    testWidgets('a hit that only the catch-up finds shows up without a new '
        'keystroke', (tester) async {
      addRoom(_secretRoom, 'Secret book club');
      final gate = Completer<void>();
      GlobalSearchController.catchUpFor = (client, cancel) async {
        await gate.future;
        MessageIndex.of(
          client,
        ).add(indexed(_secretRoom, 1, 'needle found late'));
        return 1;
      };
      addTearDown(
        () =>
            GlobalSearchController.catchUpFor = (client, cancel) =>
                IndexFeeder.of(client).catchUp(cancel: cancel),
      );
      await harness.open(tester, path: '/rooms/search');
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      final chip = find.descendant(
        of: find.byType(SearchChipsBar),
        matching: find.text(l10n.messages),
      );
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await harness.settle(tester, rounds: 2);
      await type(tester, 'needle');
      expect(find.byType(MessageHitTile), findsNothing);
      gate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.byType(MessageHitTile), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('tapping a hit opens the chat at that message', (tester) async {
      addRoom(_secretRoom, 'Secret book club');
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      index.add(indexed(_secretRoom, 1, 'needle in a haystack'));
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      await tester.tap(find.byType(MessageHitTile).first);
      await harness.settle(tester, rounds: 3);
      expect(Uri.parse(location()).path, '/rooms/$_secretRoom');
      expect(
        Uri.parse(location()).queryParameters['event'],
        r'$idx1:example.org',
      );
      await harness.finish(tester);
    });

    testWidgets('a hit with an id that is no event id is not opened', (
      tester,
    ) async {
      addRoom(_secretRoom, 'Secret book club');
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      index.add(
        IndexedMessage(
          roomId: _secretRoom,
          eventId: 'not-an-event-id',
          senderId: '@alice:example.org',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          kind: SearchKind.text,
          text: 'needle here',
        ),
      );
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      await tester.tap(find.byType(MessageHitTile).first);
      await harness.settle(tester, rounds: 3);
      expect(Uri.parse(location()).path, '/rooms/search');
      await harness.finish(tester);
    });

    testWidgets('an empty query sends nothing, also after the debounce', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      api.clear();
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'a');
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), '');
      await tester.pump(const Duration(seconds: 2));
      expect(api.requests('/search', method: 'POST'), isEmpty);
      expect(api.requests('/user_directory', method: 'POST'), isEmpty);
      expect(api.requests('/publicRooms'), isEmpty);
      await harness.finish(tester);
    });

    testWidgets('nothing found shows the empty state', (tester) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'zzzzzz');
      expect(find.text(l10n(tester).nothingFound), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a message hidden by the retention timer is not shown', (
      tester,
    ) async {
      final room = addRoom(_secretRoom, 'Secret book club');
      room.setState(
        Event(
          type: 'm.room.retention',
          stateKey: '',
          content: {
            'max_lifetime': const Duration(days: 1).inMilliseconds,
            'expire_on_clients': true,
          },
          room: room,
          eventId: r'$ret:example.org',
          senderId: '@alice:example.org',
          originServerTs: DateTime(2025),
        ),
      );
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      index.add(
        IndexedMessage(
          roomId: _secretRoom,
          eventId: r'$old:example.org',
          senderId: '@alice:example.org',
          timestamp: DateTime.now()
              .subtract(const Duration(days: 3))
              .millisecondsSinceEpoch,
          kind: SearchKind.text,
          text: 'expired needle',
        ),
      );
      index.add(indexed(_secretRoom, 2, 'fresh needle'));
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(
        find.textContaining('fresh needle', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('expired needle', findRichText: true),
        findsNothing,
      );
      await harness.finish(tester);
    });

    testWidgets(
      'a message that expires while the page is open is hidden at once',
      (tester) async {
        final room = addRoom(_secretRoom, 'Secret book club');
        room.setState(
          Event(
            type: 'm.room.retention',
            stateKey: '',
            content: {
              'max_lifetime': const Duration(days: 1).inMilliseconds,
              'expire_on_clients': true,
            },
            room: room,
            eventId: r'$ret2:example.org',
            senderId: '@alice:example.org',
            originServerTs: DateTime(2025),
          ),
        );
        await harness.open(tester, path: '/rooms/search');
        final index = MessageIndex.of(harness.client);
        await tester.runAsync(() => index.ready);
        index.add(
          IndexedMessage(
            roomId: _secretRoom,
            eventId: r'$late:example.org',
            senderId: '@alice:example.org',
            timestamp: DateTime.now()
                .subtract(const Duration(days: 3))
                .millisecondsSinceEpoch,
            kind: SearchKind.text,
            text: 'late expired needle',
          ),
        );
        index.add(indexed(_secretRoom, 3, 'late fresh needle'));
        await type(tester, 'needle');
        expect(
          find.textContaining('late fresh needle', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('late expired needle', findRichText: true),
          findsNothing,
        );
        await harness.finish(tester);
      },
    );

    testWidgets('a chat that was left is not shown in the results', (
      tester,
    ) async {
      addRoom(_secretRoom, 'Secret book club');
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      index.add(indexed(_secretRoom, 1, 'needle one'));
      index.add(indexed('!gone:example.org', 2, 'needle two'));
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(
        find.textContaining('needle one', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('needle two', findRichText: true),
        findsNothing,
      );
      await harness.finish(tester);
    });
  });

  group('what leaves the device', () {
    testWidgets(
      'the server is asked after 300 ms, for unencrypted chats only',
      (tester) async {
        addRoom(_secretRoom, 'Secret book club');
        addRoom(_openRoom, 'Open air', encrypted: false);
        searchHandler = (_) =>
            hits([serverEvent(_openRoom, 1, 'server needle')]);
        await harness.open(tester, path: '/rooms/search');
        api.clear();
        await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'needle');
        await tester.pump(const Duration(milliseconds: 200));
        expect(api.requests('/search', method: 'POST'), isEmpty);
        await tester.pump(const Duration(milliseconds: 150));
        await harness.settle(tester, rounds: 3);
        final posts = api.requests('/_matrix/client/v3/search', method: 'POST');
        expect(posts, hasLength(1));
        final body = posts.single.json! as Map;
        final criteria =
            (body['search_categories'] as Map)['room_events'] as Map;
        expect((criteria['filter'] as Map)['rooms'], contains(_openRoom));
        expect(
          (criteria['filter'] as Map)['rooms'],
          isNot(contains(_secretRoom)),
        );
        expect(
          find.textContaining('server needle', findRichText: true),
          findsOneWidget,
        );
        await harness.finish(tester);
      },
    );

    testWidgets('no server search when every chat is encrypted', (
      tester,
    ) async {
      addRoom(_secretRoom, 'Secret book club');
      await harness.open(tester, path: '/rooms/search');
      api.clear();
      await type(tester, 'needle');
      expect(
        api.requests('/_matrix/client/v3/search', method: 'POST'),
        isEmpty,
      );
      await harness.finish(tester);
    });

    testWidgets('people are searched from two characters on', (tester) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      api.clear();
      await type(tester, 'a');
      expect(api.requests('user_directory/search', method: 'POST'), isEmpty);
      await type(tester, 'ab');
      expect(
        api.requests('user_directory/search', method: 'POST'),
        hasLength(1),
      );
      await harness.finish(tester);
    });

    testWidgets(
      'public rooms are asked on the own server unless another one was chosen',
      (tester) async {
        addRoom(_openRoom, 'Open air', encrypted: false);
        await harness.open(tester, path: '/rooms/search');
        api.clear();
        await type(tester, 'abc');
        final own = api.requests('/publicRooms', method: 'POST');
        expect(own, hasLength(1));
        expect(own.single.url.queryParameters.containsKey('server'), isFalse);
        await harness.finish(tester);
      },
    );

    Finder inResults(String text) => find.descendant(
      of: find.byKey(GlobalSearchView.resultsKey),
      matching: find.textContaining(text),
    );

    testWidgets('a typed alias that is not published is resolved', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      api.getResponder = (url) => url.path.contains('/directory/room/')
          ? {'room_id': '!resolved:example.org', 'servers': <Object?>[]}
          : null;
      await harness.open(tester, path: '/rooms/search');
      await type(tester, '#hidden:example.org');
      expect(inResults('#hidden:example.org'), findsWidgets);
      await harness.finish(tester);
    });

    testWidgets('an alias that does not resolve changes nothing', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      api.onRequest = (request) async {
        if (request.url.path.contains('/directory/room/')) {
          throw Exception('offline');
        }
      };
      await harness.open(tester, path: '/rooms/search');
      await type(tester, '#missing:example.org');
      expect(inResults('#missing:example.org'), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });

    testWidgets('a typed user id is offered even when the directory has none', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      await type(tester, '@bob:example.org');
      expect(inResults('@bob:example.org'), findsWidgets);
      await harness.finish(tester);
    });

    testWidgets('a chosen directory server is shown and used', (tester) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await AppSettings.store.setString(
        GlobalSearchController.serverStoreKey,
        'other.example',
      );
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      api.clear();
      await type(tester, 'abc');
      final requests = api.requests('/publicRooms', method: 'POST');
      expect(requests.single.url.queryParameters['server'], 'other.example');
      expect(find.text('Server: other.example'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('the query is in request bodies only and never in logs', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      Logs().outputEvents.clear();
      await harness.open(tester, path: '/rooms/search');
      api.clear();
      await type(tester, 'SENTINELQUERYWORD');
      expect(
        sentQuery('sentinelqueryword') || sentQuery('SENTINELQUERYWORD'),
        isTrue,
      );
      for (final request in api.log) {
        expect(
          request.url.toString().toLowerCase(),
          isNot(contains('sentinelqueryword')),
        );
        if (!sentQuery('x') &&
            request.body.toLowerCase().contains('sentinelqueryword')) {
          expect(request.method, 'POST');
        }
      }
      final logs = Logs().outputEvents
          .map((e) => '${e.title} ${e.exception} ${e.stackTrace}')
          .join('\n')
          .toLowerCase();
      expect(logs, isNot(contains('sentinelqueryword')));
      await harness.finish(tester);
    });

    testWidgets('a search answer far over the size cap is an error, no hits', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      searchHandler = (_) => hits([
        serverEvent(_openRoom, 1, 'x' * (ServerSearch.maxResponseBytes + 1024)),
      ]);
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(find.byType(SearchRetryRow), findsOneWidget);
      expect(find.byType(MessageHitTile), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });

    testWidgets('a failing server search shows a retry row, no snackbar', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      searchHandler = (_) => throw StateError('boom');
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(find.text(l10n(tester).searchError), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      searchHandler = (_) =>
          hits([serverEvent(_openRoom, 1, 'recovered needle')]);
      await tester.tap(find.text(l10n(tester).searchError));
      await harness.settle(tester, rounds: 3);
      expect(
        find.textContaining('recovered needle', findRichText: true),
        findsOneWidget,
      );
      await harness.finish(tester);
    });
  });

  group('async races', () {
    testWidgets('a slow answer for an old query never replaces a newer one', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      final gate = Completer<void>();
      var firstSeen = false;
      api.onRequest = (request) async {
        if (!request.url.path.endsWith('/v3/search') ||
            request.method != 'POST') {
          return;
        }
        if (firstSeen) return;
        firstSeen = true;
        await gate.future;
      };
      searchHandler = (body) {
        final decoded = jsonDecode(body! as String) as Map;
        final term =
            ((decoded['search_categories'] as Map)['room_events']
                as Map)['search_term'];
        return hits([
          serverEvent(_openRoom, term == 'ne' ? 1 : 2, '$term result'),
        ]);
      };
      await harness.open(tester, path: '/rooms/search');
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'ne');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'need');
      await tester.pump(const Duration(milliseconds: 350));
      await harness.settle(tester, rounds: 3);
      expect(
        find.textContaining('need result', findRichText: true),
        findsOneWidget,
      );
      gate.complete();
      await harness.settle(tester, rounds: 3);
      expect(
        find.textContaining('ne result', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('need result', findRichText: true),
        findsOneWidget,
      );
      await harness.finish(tester);
    });

    testWidgets('a slow failure of an old query shows no error', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      final gate = Completer<void>();
      var served = 0;
      api.onRequest = (request) async {
        if (!request.url.path.endsWith('/v3/search') ||
            request.method != 'POST') {
          return;
        }
        if (served++ == 0) await gate.future;
      };
      searchHandler = (body) {
        final decoded = jsonDecode(body! as String) as Map;
        final term =
            ((decoded['search_categories'] as Map)['room_events']
                as Map)['search_term'];
        if (term == 'ne') throw StateError('old query fails late');
        return hits([serverEvent(_openRoom, 2, '$term result')]);
      };
      await harness.open(tester, path: '/rooms/search');
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'ne');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'need');
      await tester.pump(const Duration(milliseconds: 350));
      await harness.settle(tester, rounds: 3);
      gate.complete();
      await harness.settle(tester, rounds: 3);
      expect(find.text(l10n(tester).searchError), findsNothing);
      expect(
        find.textContaining('need result', findRichText: true),
        findsOneWidget,
      );
      await harness.finish(tester);
    });

    testWidgets('leaving the page while a search is pending throws nothing', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      final gate = Completer<void>();
      api.onRequest = (request) async {
        if (request.url.path.endsWith('/v3/search') &&
            request.method == 'POST') {
          await gate.future;
        }
      };
      searchHandler = (_) => hits([serverEvent(_openRoom, 1, 'late needle')]);
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      FluffyChatApp.router.go('/rooms');
      await harness.settle(tester, rounds: 3);
      gate.complete();
      await harness.settle(tester, rounds: 3);
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });
  });

  group('notices', () {
    testWidgets('encrypted chats: this device only, with the count', (
      tester,
    ) async {
      addRoom(_secretRoom, 'Secret book club');
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      index.add(indexed(_secretRoom, 1, 'needle'));
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(find.text(l10n(tester).searchNoticePersistent(1)), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('an unencrypted database keeps the index in memory: said so', (
      tester,
    ) async {
      unencryptedClientsThisSession.add('x');
      addRoom(_secretRoom, 'Secret book club');
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(find.text(l10n(tester).searchNoticeMemoryOnly), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('unencrypted chats: said that the server searches them', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      await type(tester, 'needle');
      expect(find.text(l10n(tester).searchNoticeServer), findsOneWidget);
      await harness.finish(tester);
    });
  });

  group('filters', () {
    testWidgets('the sheet applies Files and the chip follows', (tester) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      await tester.tap(find.byKey(GlobalSearchView.filtersKey));
      await harness.settle(tester, rounds: 3);
      await tester.tap(
        find.descendant(
          of: find.byType(SearchFilterSheet),
          matching: find.text(l10n(tester).searchTypeFiles),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(SearchFilterSheet.applyKey));
      await harness.settle(tester, rounds: 3);
      expect(find.text('1'), findsWidgets);
      final chip = find.bySemanticsLabel(l10n(tester).files);
      expect(chip, findsWidgets);
      await harness.finish(tester);
    });

    testWidgets(
      'a filter-only search reads the stored events and sends no search request',
      (tester) async {
        addRoom(_openRoom, 'Open air', encrypted: false);
        await harness.open(tester, path: '/rooms/search');
        api.clear();
        await tester.tap(find.byKey(GlobalSearchView.filtersKey));
        await harness.settle(tester, rounds: 3);
        await tester.tap(
          find.descendant(
            of: find.byType(SearchFilterSheet),
            matching: find.text(l10n(tester).searchTypeFiles),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(SearchFilterSheet.applyKey));
        await harness.settle(tester, rounds: 3);
        expect(
          api.requests('/_matrix/client/v3/search', method: 'POST'),
          isEmpty,
        );
        expect(find.text(l10n(tester).searchNoticeFilterOnly), findsOneWidget);
        await harness.finish(tester);
      },
    );

    testWidgets('retrying a failed filter-only search reads the events again', (
      tester,
    ) async {
      addRoom(_openRoom, 'Open air', encrypted: false);
      await harness.open(tester, path: '/rooms/search');
      final controller = tester.state<GlobalSearchController>(
        find.byType(GlobalSearch),
      );
      var reads = 0;
      controller.scanFor = (client) => UnencryptedScan(
        client,
        reader: (room, limit) async {
          reads++;
          if (reads == 1) throw Exception('database busy');
          return <Event>[];
        },
      );
      api.clear();
      await tester.tap(find.byKey(GlobalSearchView.filtersKey));
      await harness.settle(tester, rounds: 3);
      await tester.tap(
        find.descendant(
          of: find.byType(SearchFilterSheet),
          matching: find.text(l10n(tester).searchTypeFiles),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(SearchFilterSheet.applyKey));
      await harness.settle(tester, rounds: 3);
      expect(reads, 1);
      expect(controller.serverStatus, SourceStatus.error);
      await tester.tap(find.text(l10n(tester).searchError));
      await harness.settle(tester, rounds: 3);
      expect(reads, 2);
      expect(controller.serverStatus, SourceStatus.done);
      expect(
        api.requests('/_matrix/client/v3/search', method: 'POST'),
        isEmpty,
      );
      await harness.finish(tester);
    });
  });
}
