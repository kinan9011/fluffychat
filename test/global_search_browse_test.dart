// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat_list/space_switcher.dart';
import 'package:odango/pages/global_search/global_search.dart';
import 'package:odango/pages/global_search/global_search_view.dart';
import 'package:odango/pages/global_search/search_result_widgets.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

Map<String, Object?> _room(int n, {String? type}) => {
  'room_id': '!room$n:example.org',
  'name': 'Public room $n',
  'num_joined_members': n,
  'world_readable': false,
  'guest_can_join': false,
  'room_type': ?type,
};

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  var directory = (Map<String, Object?> body) => <String, Object?>{
    'chunk': <Object?>[],
    'total_room_count_estimate': 0,
  };

  setUpAll(harness.setUpAll);

  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    directory = (_) => {'chunk': <Object?>[], 'total_room_count_estimate': 0};
    api.api['POST']!['/client/v3/publicRooms'] = (req) =>
        directory(jsonDecode(req as String) as Map<String, Object?>);
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': <Object?>[],
      'limited': false,
    };
    harness.resetRooms();
    MessageIndex.forget(harness.client);
  });
  tearDown(harness.tearDown);

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(GlobalSearchView.fieldKey), text);
    await tester.pump(const Duration(milliseconds: 350));
    await harness.settle(tester, rounds: 3);
  }

  Future<void> tapChip(
    WidgetTester tester,
    String label, {
    double delta = 50,
  }) async {
    final chip = find.descendant(
      of: find.byType(SearchChipsBar),
      matching: find.text(label),
    );
    await tester.scrollUntilVisible(
      chip,
      delta,
      scrollable: find.descendant(
        of: find.byType(SearchChipsBar),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await harness.settle(tester);
  }

  GlobalSearchController controllerOf(WidgetTester tester) =>
      tester.state<GlobalSearchController>(find.byType(GlobalSearch));

  Finder resultsScrollable() => find.descendant(
    of: find.byKey(GlobalSearchView.resultsKey),
    matching: find.byType(Scrollable),
  );

  List<RecordedRequest> directoryRequests() =>
      api.requests('/publicRooms', method: 'POST');

  group('browsing the public directory without a search word', () {
    testWidgets(
      'the explore action lists rooms and spaces before anything is typed',
      (tester) async {
        directory = (_) => {
          'chunk': [_room(1), _room(2, type: 'm.space')],
          'total_room_count_estimate': 2,
        };
        await harness.open(tester, path: '/rooms/search?section=public');
        await harness.settle(tester);
        final requests = directoryRequests();
        expect(requests, hasLength(1));
        final body = requests.single.json! as Map<String, Object?>;
        expect(body.containsKey('filter'), isFalse);
        expect(body['limit'], 20);
        expect(find.byType(PublicRoomTile), findsNWidgets(2));
        expect(find.text('Public room 1'), findsOneWidget);
        final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
        expect(find.text(l10n.publicSpaces.toUpperCase()), findsOneWidget);
        await harness.finish(tester);
      },
    );

    testWidgets('the Public rooms chip browses without a word, All does not', (
      tester,
    ) async {
      directory = (_) => {
        'chunk': [_room(1)],
        'total_room_count_estimate': 1,
      };
      await harness.open(tester, path: '/rooms/search');
      expect(directoryRequests(), isEmpty);
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      await tapChip(tester, l10n.publicRooms);
      expect(directoryRequests(), hasLength(1));
      expect(find.byType(PublicRoomTile), findsOneWidget);
      await tapChip(tester, l10n.all, delta: -50);
      expect(find.byType(PublicRoomTile), findsNothing);
      expect(directoryRequests(), hasLength(1));
      await harness.finish(tester);
    });

    testWidgets('an empty directory says nothing was found', (tester) async {
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      expect(find.text(l10n.nothingFound), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('more pages are loaded on request and stop at the caps', (
      tester,
    ) async {
      var page = 0;
      directory = (body) {
        page++;
        return {
          'chunk': [for (var i = 0; i < 20; i++) _room(page * 100 + i)],
          'next_batch': 'page$page',
          'total_room_count_estimate': 1000,
        };
      };
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      for (var i = 0; i < 10; i++) {
        final more = find.text(l10n.loadMore);
        if (!controllerOf(tester).canLoadMorePublic) break;
        await tester.scrollUntilVisible(
          more,
          300,
          scrollable: resultsScrollable(),
        );
        await tester.tap(more);
        await harness.settle(tester);
      }
      final requests = directoryRequests();
      expect(requests, hasLength(GlobalSearchController.maxPublicPages));
      final second = requests[1].json! as Map<String, Object?>;
      expect(second['since'], 'page1');
      expect(
        controllerOf(tester).publicRooms.length,
        lessThanOrEqualTo(GlobalSearchController.maxPublicRooms),
      );
      expect(controllerOf(tester).canLoadMorePublic, isFalse);
      await harness.finish(tester);
    });

    testWidgets('five pages are the most that are loaded, whatever the size', (
      tester,
    ) async {
      var page = 0;
      directory = (_) {
        page++;
        return {
          'chunk': [for (var i = 0; i < 5; i++) _room(page * 100 + i)],
          'next_batch': 'page$page',
          'total_room_count_estimate': 1000,
        };
      };
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      final controller = controllerOf(tester);
      for (var i = 0; i < 8; i++) {
        unawaited(controller.loadMorePublic());
        await harness.settle(tester, rounds: 2);
      }
      expect(
        directoryRequests(),
        hasLength(GlobalSearchController.maxPublicPages),
      );
      expect(controller.publicRooms, hasLength(25));
      expect(controller.canLoadMorePublic, isFalse);
      await harness.finish(tester);
    });

    testWidgets('loading more does not look the typed alias up again', (
      tester,
    ) async {
      directory = (_) => {
        'chunk': [_room(1)],
        'next_batch': 'page1',
        'total_room_count_estimate': 40,
      };
      api.getResponder = (url) => url.path.contains('/directory/room/')
          ? {'room_id': '!resolved:example.org', 'servers': <Object?>[]}
          : null;
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      await type(tester, '#hidden:example.org');
      expect(api.requests('/directory/room/'), hasLength(1));
      unawaited(controllerOf(tester).loadMorePublic());
      await harness.settle(tester);
      expect(api.requests('/directory/room/'), hasLength(1));
      expect(directoryRequests().last.json, containsPair('since', 'page1'));
      await harness.finish(tester);
    });

    testWidgets('a server that ignores the page size cannot fill the page', (
      tester,
    ) async {
      var page = 0;
      directory = (_) {
        page++;
        return {
          'chunk': [for (var i = 0; i < 60; i++) _room(page * 100 + i)],
          'next_batch': 'page$page',
          'total_room_count_estimate': 1000,
        };
      };
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      final controller = controllerOf(tester);
      unawaited(controller.loadMorePublic());
      await harness.settle(tester);
      expect(
        controller.publicRooms,
        hasLength(GlobalSearchController.maxPublicRooms),
      );
      expect(controller.canLoadMorePublic, isFalse);
      await controller.loadMorePublic();
      expect(directoryRequests(), hasLength(2));
      await harness.finish(tester);
    });

    testWidgets('Nothing found is not shown while the word waits for the '
        'debounce', (tester) async {
      await harness.open(tester, path: '/rooms/search');
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'zzzz');
      await tester.pump(const Duration(milliseconds: 100));
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      expect(find.text(l10n.nothingFound), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await harness.settle(tester);
      expect(find.text(l10n.nothingFound), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a room listed twice shows once, bad ids are dropped', (
      tester,
    ) async {
      directory = (_) => {
        'chunk': [
          _room(1),
          _room(1),
          {..._room(2), 'room_id': 'not-a-room-id'},
        ],
        'total_room_count_estimate': 3,
      };
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      expect(find.byType(PublicRoomTile), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('page at 320x480 with the keyboard open and text x2', (
      tester,
    ) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      directory = (_) => {
        'chunk': [
          for (var i = 0; i < 6; i++)
            _room(i, type: i.isEven ? 'm.space' : null),
        ],
        'total_room_count_estimate': 6,
      };
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: '/rooms/search?section=public',
      );
      await harness.settle(tester);
      final field = tester.getRect(find.byKey(GlobalSearchView.fieldKey));
      expect(field.bottom, lessThanOrEqualTo(480 - 300 + 1));
      final scrollable = find.descendant(
        of: find.byKey(GlobalSearchView.resultsKey),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Public room 4'),
        100,
        scrollable: scrollable,
      );
      expect(tester.takeException(), isNull);
      for (final tile in tester.widgetList<PublicRoomTile>(
        find.byType(PublicRoomTile),
      )) {
        expect(tile.chunk.roomId, startsWith('!room'));
      }
      await harness.finish(tester);
    });
  });

  testWidgets('Explore public spaces of the chat list opens the directory', (
    tester,
  ) async {
    final space = Room(
      id: '!space:example.org',
      client: harness.client,
      membership: Membership.join,
    );
    space.setState(
      Event(
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': RoomCreationTypes.mSpace},
        room: space,
        eventId: r'$create:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    harness.client.rooms.add(space);
    await AppSettings.spaceNavigation.setItem('switcher');
    directory = (_) => {
      'chunk': [_room(1, type: 'm.space')],
      'total_room_count_estimate': 1,
    };
    await harness.open(tester, path: '/rooms');
    await tester.tap(find.byType(SpaceSwitcherChip));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.text('Explore public spaces'));
    await harness.settle(tester);
    final uri = FluffyChatApp.router.routeInformationProvider.value.uri;
    expect(uri.path, '/rooms/search');
    expect(uri.queryParameters['section'], 'public');
    expect(directoryRequests(), hasLength(1));
    expect(find.byType(PublicRoomTile), findsOneWidget);
    await harness.finish(tester);
  });

  group('the directory server of the Public rooms section', () {
    Future<void> chooseServer() => AppSettings.store.setString(
      GlobalSearchController.serverStoreKey,
      'other.example',
    );

    testWidgets('All asks only the own server, the typed word stays there', (
      tester,
    ) async {
      await chooseServer();
      await harness.open(tester, path: '/rooms/search');
      api.clear();
      await type(tester, 'sentinelword');
      final requests = directoryRequests();
      expect(requests, hasLength(1));
      expect(
        requests.single.url.queryParameters.containsKey('server'),
        isFalse,
      );
      expect(find.text('Server: other.example'), findsNothing);
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      expect(
        find.text(l10n.searchNoticeDirectory('other.example')),
        findsNothing,
      );
      await harness.finish(tester);
    });

    testWidgets('the Public rooms section uses the chosen server and says so', (
      tester,
    ) async {
      await chooseServer();
      await harness.open(tester, path: '/rooms/search?section=public');
      await harness.settle(tester);
      api.clear();
      await type(tester, 'sentinelword');
      final requests = directoryRequests();
      expect(requests.last.url.queryParameters['server'], 'other.example');
      expect(find.text('Server: other.example'), findsOneWidget);
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      expect(
        find.text(l10n.searchNoticeDirectory('other.example')),
        findsOneWidget,
      );
      await harness.finish(tester);
    });

    testWidgets('local sections never ask a directory', (tester) async {
      await chooseServer();
      await harness.open(tester, path: '/rooms/search');
      final l10n = L10n.of(tester.element(find.byType(GlobalSearch)));
      for (final label in [l10n.messages, l10n.files]) {
        await tester.tap(find.text(label).first);
        await harness.settle(tester, rounds: 2);
        api.clear();
        await type(tester, 'sentinelword');
        expect(directoryRequests(), isEmpty);
        await tester.enterText(find.byKey(GlobalSearchView.fieldKey), '');
        await harness.settle(tester, rounds: 2);
      }
      await harness.finish(tester);
    });
  });
}
