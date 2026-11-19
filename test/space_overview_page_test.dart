// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/space_overview/space_overview.dart';
import 'package:odango/pages/space_overview/space_overview_view.dart';
import 'package:odango/utils/spaces/space_hierarchy.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

const _space = '!space:example.org';
const _sub = '!sub:example.org';
const _roomA = '!a:example.org';
const _roomB = '!b:example.org';
const _roomC = '!c:example.org';

Map<String, Object?> entry(
  String id, {
  String? name,
  String? type,
  int members = 4,
  int children = 0,
}) => {
  'room_id': id,
  'name': name ?? 'Room $id',
  'room_type': type,
  'num_joined_members': members,
  'children_state': List<Object?>.filled(children, {}),
  'guest_can_join': false,
  'world_readable': false,
};

Map<String, Object?> pageOf(List<Map<String, Object?>> rooms, {String? next}) =>
    {'rooms': rooms, 'next_batch': ?next};

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  final answers = <String, Object? Function(String? from)>{};
  final gates = <Completer<void>>[];

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.onRequest = null;
    answers.clear();
    gates.clear();
    api.getResponder = (url) {
      if (!url.path.endsWith('/hierarchy')) return null;
      final segments = url.pathSegments;
      final id = Uri.decodeComponent(segments[segments.length - 2]);
      return answers[id]?.call(url.queryParameters['from']);
    };
    harness.resetRooms();
  });
  tearDown(harness.tearDown);

  Room addSpace(
    String id,
    String name, {
    List<String> children = const [],
    Set<String> suggested = const {},
    Object? suggestedValue = true,
    bool admin = false,
    List<String> via = const ['example.org'],
  }) {
    final room = Room(
      id: id,
      client: harness.client,
      membership: Membership.join,
    );
    void put(Event event) => room.setState(event);
    put(
      Event(
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': RoomCreationTypes.mSpace},
        room: room,
        eventId: '\$create$id',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
    put(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': name},
        room: room,
        eventId: '\$name$id',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
    put(
      Event(
        type: EventTypes.RoomPowerLevels,
        stateKey: '',
        content: {
          'users': {harness.client.userID!: admin ? 100 : 0},
          'state_default': 50,
        },
        room: room,
        eventId: '\$pl$id',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
    for (final child in children) {
      put(
        Event(
          type: EventTypes.SpaceChild,
          stateKey: child,
          content: {
            'via': via,
            if (suggested.contains(child)) 'suggested': suggestedValue,
          },
          room: room,
          eventId: '\$child$id$child',
          senderId: '@admin:example.org',
          originServerTs: DateTime(2030),
        ),
      );
    }
    harness.client.rooms.add(room);
    return room;
  }

  void joinRoom(String id, {bool space = false}) {
    final room = Room(
      id: id,
      client: harness.client,
      membership: Membership.join,
    );
    if (space) {
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          stateKey: '',
          content: {'type': RoomCreationTypes.mSpace},
          room: room,
          eventId: '\$create$id',
          senderId: '@admin:example.org',
          originServerTs: DateTime(2030),
        ),
      );
    }
    harness.client.rooms.add(room);
  }

  String path(String id, {String? trail}) => Uri(
    pathSegments: ['rooms', 'space', id],
    queryParameters: {'trail': ?trail},
  ).toString();

  String location() =>
      FluffyChatApp.router.routerDelegate.currentConfiguration.uri.toString();

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(SpaceOverview)));

  SpaceOverview top(WidgetTester tester) =>
      tester.widgetList<SpaceOverview>(find.byType(SpaceOverview)).last;

  SpaceOverviewController controller(WidgetTester tester) =>
      tester.state<SpaceOverviewController>(find.byType(SpaceOverview));

  List<RecordedRequest> hierarchyRequests() =>
      api.log.where((r) => r.path.endsWith('/hierarchy')).toList();

  group('the lists', () {
    testWidgets('Joined and Suggested come from the space state', (
      tester,
    ) async {
      addSpace(
        _space,
        'Berlin Makers',
        children: [_roomA, _roomB, _roomC],
        suggested: {_roomB},
      );
      joinRoom(_roomA);
      answers[_space] = (_) => pageOf([
        entry(_roomA, name: 'General'),
        entry(_roomB, name: 'Help desk'),
        entry(_roomC, name: 'Events'),
      ]);
      await harness.open(tester, path: path(_space));
      expect(find.text('Berlin Makers'), findsWidgets);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Help desk'), findsNothing);
      expect(find.text(l10n(tester).spaceTabJoined(1)), findsOneWidget);
      expect(find.text(l10n(tester).spaceTabSuggested(1)), findsOneWidget);
      await tester.tap(find.text(l10n(tester).spaceTabSuggested(1)));
      await tester.pump();
      expect(find.text('Help desk'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text(l10n(tester).spaceOtherRooms), findsOneWidget);
      expect(find.text('General'), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('suggested must be the boolean true, the string is ignored', (
      tester,
    ) async {
      addSpace(
        _space,
        'S',
        children: [_roomA],
        suggested: {_roomA},
        suggestedValue: 'true',
      );
      answers[_space] = (_) => pageOf([entry(_roomA, name: 'Alpha')]);
      await harness.open(tester, path: path(_space));
      expect(find.text(l10n(tester).spaceTabSuggested(0)), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a space that is not joined has one list and no tabs', (
      tester,
    ) async {
      answers[_space] = (_) => pageOf([entry(_roomA, name: 'Alpha')]);
      await harness.open(tester, path: path(_space));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text(l10n(tester).spaceTabJoined(0)), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('only direct children are asked for', (tester) async {
      addSpace(_space, 'S');
      answers[_space] = (_) => pageOf([]);
      await harness.open(tester, path: path(_space));
      final request = hierarchyRequests().single;
      expect(request.url.queryParameters['max_depth'], '1');
      expect(request.url.queryParameters.containsKey('from'), isFalse);
      await harness.finish(tester);
    });

    testWidgets('hostile names are shown cleaned', (tester) async {
      addSpace(_space, 'S');
      answers[_space] = (_) =>
          pageOf([entry(_roomA, name: 'Ev\u202Eil\u200B')]);
      await harness.open(tester, path: path(_space));
      expect(find.textContaining('\u202E'), findsNothing);
      expect(find.textContaining('\u200B'), findsNothing);
      await harness.finish(tester);
    });
  });

  group('subspaces', () {
    testWidgets('a subspace is entered with the trail in the route', (
      tester,
    ) async {
      addSpace(_space, 'S', children: [_sub]);
      joinRoom(_sub, space: true);
      answers[_space] = (_) => pageOf([
        entry(_sub, name: 'Translations', type: 'm.space', children: 5),
      ]);
      joinRoom(_roomA);
      answers[_sub] = (_) => pageOf([entry(_roomA, name: 'German')]);
      await harness.open(tester, path: path(_space));
      await tester.tap(find.text('Translations'));
      await harness.settle(tester, rounds: 3);
      expect(top(tester).spaceId, _sub);
      expect(top(tester).trail.ids, [_space]);
      expect(find.text('German'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a space on the trail is not entered again (cycle)', (
      tester,
    ) async {
      addSpace(_sub, 'Sub', children: [_space]);
      joinRoom(_space, space: true);
      answers[_sub] = (_) =>
          pageOf([entry(_space, name: 'Parent', type: 'm.space', children: 1)]);
      await harness.open(tester, path: path(_sub, trail: _space));
      await tester.tap(find.text('Parent'));
      await harness.settle(tester, rounds: 3);
      expect(find.byType(SpaceOverview), findsOneWidget);
      expect(top(tester).spaceId, _sub);
      expect(find.text(l10n(tester).spaceAlreadyOpen), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a trail at depth 8 enters nothing more', (tester) async {
      final trail = [for (var n = 0; n < 7; n++) '!t$n:example.org'].join(',');
      answers[_sub] = (_) => pageOf([
        entry(
          '!deeper:example.org',
          name: 'Deeper',
          type: 'm.space',
          children: 1,
        ),
      ]);
      await harness.open(tester, path: path(_sub, trail: trail));
      await tester.tap(find.text('Deeper'));
      await harness.settle(tester, rounds: 3);
      expect(find.byType(SpaceOverview), findsOneWidget);
      expect(top(tester).spaceId, _sub);
      await harness.finish(tester);
    });
  });

  group('joining', () {
    testWidgets(
      'nothing is joined before the button is tapped, via comes from the space state',
      (tester) async {
        addSpace(
          _space,
          'S',
          children: [_roomA],
          suggested: {_roomA},
          via: ['good.example', 'evil/path', 'user@evil.example'],
        );
        answers[_space] = (_) => pageOf([entry(_roomA, name: 'Alpha')]);
        await harness.open(tester, path: path(_space));
        await tester.tap(find.text(l10n(tester).spaceTabSuggested(1)));
        await tester.pump();
        expect(api.requests('/join/', method: 'POST'), isEmpty);
        await tester.tap(find.text(l10n(tester).join));
        await harness.settle(tester, rounds: 4);
        final joins = api.requests('/join/', method: 'POST');
        expect(joins, hasLength(1));
        expect(joins.single.url.queryParametersAll['via'], ['good.example']);
        await harness.finish(tester);
      },
    );
  });

  group('joining from a space that is not joined', () {
    testWidgets('the servers of the room and the space are the way in', (
      tester,
    ) async {
      const room = '!far:far.example';
      answers[_space] = (_) => pageOf([entry(room, name: 'Far')]);
      await harness.open(tester, path: path(_space));
      await tester.tap(find.text(l10n(tester).join));
      await harness.settle(tester, rounds: 4);
      final joins = api.requests('/join/', method: 'POST');
      expect(joins, hasLength(1));
      expect(joins.single.url.queryParametersAll['via'], [
        'far.example',
        'example.org',
      ]);
      await harness.finish(tester);
    });

    testWidgets('the hierarchy cannot add servers of its own', (tester) async {
      answers[_space] = (_) => pageOf([
        {
          ...entry(_roomA, name: 'Alpha'),
          'children_state': [
            {
              'type': 'm.space.child',
              'state_key': _roomA,
              'content': {
                'via': ['evil.example'],
              },
            },
          ],
        },
      ]);
      await harness.open(tester, path: path(_space));
      await tester.tap(find.text(l10n(tester).join));
      await harness.settle(tester, rounds: 4);
      final joins = api.requests('/join/', method: 'POST');
      expect(joins.single.url.queryParametersAll['via'], ['example.org']);
      await harness.finish(tester);
    });
  });

  group('paging', () {
    testWidgets('Load more continues with the token', (tester) async {
      // not joined: one plain list

      answers[_space] = (from) => from == null
          ? pageOf([entry(_roomA, name: 'One')], next: 'tok1')
          : pageOf([entry(_roomB, name: 'Two')]);
      await harness.open(tester, path: path(_space));
      expect(find.text('One'), findsOneWidget);
      await tester.tap(find.byKey(SpaceOverviewView.loadMoreKey));
      await harness.settle(tester, rounds: 3);
      expect(find.text('Two'), findsOneWidget);
      expect(hierarchyRequests().last.url.queryParameters['from'], 'tok1');
      expect(find.byKey(SpaceOverviewView.loadMoreKey), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('the list stops at 500 rooms and says so', (tester) async {
      // not joined: one plain list

      var next = 0;
      answers[_space] = (from) {
        final start = next;
        next += 200;
        return pageOf([
          for (var n = start; n < start + 200; n++)
            entry('!r$n:example.org', name: 'R$n'),
        ], next: 'more');
      };
      await harness.open(tester, path: path(_space));
      for (var i = 0; i < 4; i++) {
        unawaited(controller(tester).load());
        await harness.settle(tester, rounds: 3);
      }
      expect(
        controller(tester).accumulator.children.length,
        HierarchyParser.maxTotalEntries,
      );
      expect(controller(tester).accumulator.capped, isTrue);
      expect(find.byKey(SpaceOverviewView.loadMoreKey), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('a change of the children starts again without a token', (
      tester,
    ) async {
      // not joined: one plain list

      answers[_space] = (from) =>
          pageOf([entry(_roomA, name: 'One')], next: 'tok1');
      await harness.open(tester, path: path(_space));
      await tester.tap(find.byKey(SpaceOverviewView.loadMoreKey));
      await harness.settle(tester, rounds: 3);
      expect(hierarchyRequests().last.url.queryParameters['from'], 'tok1');
      harness.client.onSync.add(
        SyncUpdate(
          nextBatch: 'b',
          rooms: RoomsUpdate(
            join: {
              _space: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    MatrixEvent(
                      type: EventTypes.SpaceChild,
                      stateKey: _roomB,
                      content: {
                        'via': ['example.org'],
                      },
                      senderId: '@admin:example.org',
                      eventId: r'$new:example.org',
                      originServerTs: DateTime(2031),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      );
      await harness.settle(tester, rounds: 3);
      expect(
        hierarchyRequests().last.url.queryParameters.containsKey('from'),
        isFalse,
      );
      expect(controller(tester).accumulator.children.length, 1);
      await harness.finish(tester);
    });

    testWidgets('a slow answer that was overtaken by a restart is dropped', (
      tester,
    ) async {
      // not joined: one plain list

      final gate = Completer<void>();
      var served = 0;
      api.onRequest = (request) async {
        if (!request.url.path.endsWith('/hierarchy')) return;
        if (served++ == 0) await gate.future;
      };
      answers[_space] = (from) => pageOf([
        entry(served <= 1 ? _roomA : _roomB, name: served <= 1 ? 'Old' : 'New'),
      ]);
      await harness.open(tester, path: path(_space));
      unawaited(controller(tester).load(reset: true));
      await harness.settle(tester, rounds: 3);
      expect(find.text('New'), findsOneWidget);
      gate.complete();
      await harness.settle(tester, rounds: 3);
      expect(find.text('Old'), findsNothing);
      expect(find.text('New'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a failing server shows a retry row that works', (
      tester,
    ) async {
      // not joined: one plain list

      var fail = true;
      answers[_space] = (_) => fail
          ? throw StateError('boom')
          : pageOf([entry(_roomA, name: 'Back')]);
      api.getResponder = (url) {
        if (!url.path.endsWith('/hierarchy')) return null;
        return fail ? null : answers[_space]!(null);
      };
      api.notFound.add('/hierarchy');
      await harness.open(tester, path: path(_space));
      expect(find.byKey(SpaceOverviewView.retryKey), findsOneWidget);
      fail = false;
      api.notFound.clear();
      await tester.tap(find.byKey(SpaceOverviewView.retryKey));
      await harness.settle(tester, rounds: 3);
      expect(find.text('Back'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a hierarchy answer far over the size cap is refused like '
        'an error', (tester) async {
      final huge = 'x' * (maxHierarchyBytes + 1024);
      api.getResponder = (url) => url.path.endsWith('/hierarchy')
          ? {
              'rooms': [
                {...entry(_roomA, name: 'Never shown'), 'topic': huge},
              ],
            }
          : null;
      await harness.open(tester, path: path(_space));
      await harness.settle(tester, rounds: 3);
      expect(find.byKey(SpaceOverviewView.retryKey), findsOneWidget);
      expect(find.text('Never shown'), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });

    testWidgets('leaving while a page is loading throws nothing', (
      tester,
    ) async {
      addSpace(_space, 'S');
      final gate = Completer<void>();
      api.onRequest = (request) async {
        if (request.url.path.endsWith('/hierarchy')) await gate.future;
      };
      answers[_space] = (_) => pageOf([entry(_roomA)]);
      await harness.open(tester, path: path(_space));
      FluffyChatApp.router.go('/rooms');
      await harness.settle(tester, rounds: 3);
      gate.complete();
      await harness.settle(tester, rounds: 3);
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });
  });

  group('actions and route', () {
    testWidgets('Add room is for admins only', (tester) async {
      addSpace(_space, 'S', admin: true);
      answers[_space] = (_) => pageOf([]);
      await harness.open(tester, path: path(_space));
      expect(find.text(l10n(tester).spaceAddRoom), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('a member sees no Add room', (tester) async {
      addSpace(_space, 'S');
      answers[_space] = (_) => pageOf([]);
      await harness.open(tester, path: path(_space));
      expect(find.text(l10n(tester).spaceAddRoom), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('a space id with a comma goes back to the chats', (
      tester,
    ) async {
      await harness.open(tester, path: '/rooms/space/!a,b:evil.example');
      expect(find.byType(SpaceOverview), findsNothing);
      expect(Uri.parse(location()).path, '/rooms');
      await harness.finish(tester);
    });

    testWidgets('a space id that is not a room id goes back to the chats', (
      tester,
    ) async {
      await harness.open(tester, path: '/rooms/space/not-a-room-id');
      expect(find.byType(SpaceOverview), findsNothing);
      expect(Uri.parse(location()).path, '/rooms');
      await harness.finish(tester);
    });

    testWidgets(
      'an old hierarchy cache in the preferences is removed at start',
      (tester) async {
        await AppSettings.store.setStringList(
          'spaces_history_cache!old:example.org',
          ['{"name":"Private room"}'],
        );
        await AppSettings.store.setString(
          'com.swovo.odango.search.server',
          'keep.example',
        );
        answers[_space] = (_) => pageOf([]);
        await harness.open(tester, path: path(_space));
        await harness.settle(tester, rounds: 3);
        expect(
          AppSettings.store.getKeys().where(
            (k) => k.startsWith('spaces_history_cache'),
          ),
          isEmpty,
        );
        expect(
          AppSettings.store.getString('com.swovo.odango.search.server'),
          'keep.example',
        );
        await harness.finish(tester);
      },
    );

    testWidgets('nothing is written to the preferences', (tester) async {
      addSpace(_space, 'Private space');
      answers[_space] = (_) =>
          pageOf([entry(_roomA, name: 'Secret topic room')]);
      await harness.open(tester, path: path(_space));
      final keys = AppSettings.store.getKeys();
      expect(keys.where((k) => k.contains('spaces_history_cache')), isEmpty);
      for (final key in keys) {
        expect(
          AppSettings.store.get(key).toString(),
          isNot(contains('Secret topic room')),
        );
      }
      await harness.finish(tester);
    });
  });
}
