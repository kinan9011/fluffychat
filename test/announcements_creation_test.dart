// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/space_overview/space_overview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

const _space = '!space:example.org';
const _newRoomId = '!1234:fakeServer.notExisting';

/// These tests run the real `Client.createGroupChat` and `Room.setSpaceChild`
/// of the SDK: the SDK adds `m.room.encryption` to the initial state list it
/// is handed, so a list that cannot grow breaks the creation only when the
/// real call runs.
void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.onRequest = null;
    api.getResponder = (url) =>
        url.path.endsWith('/hierarchy') ? {'rooms': <Object?>[]} : null;
    final client = harness.client;
    harness.resetRooms();
    final space = Room(id: _space, client: client, membership: Membership.join);
    void state(String type, Map<String, Object?> content) => space.setState(
      Event(
        type: type,
        stateKey: '',
        content: content,
        room: space,
        eventId: '\$$type',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
    state(EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
    state(EventTypes.RoomName, {'name': 'Berlin Makers'});
    state(EventTypes.RoomPowerLevels, {
      'users': {client.userID!: 100},
      'state_default': 50,
    });
    client.rooms.add(space);
  });
  tearDown(harness.tearDown);

  Map<Object?, Object?> createBody() {
    final posts = api.requests('/createRoom', method: 'POST');
    expect(posts, hasLength(1));
    return posts.single.json! as Map;
  }

  Iterable<Map<Object?, Object?>> initialState(String type) =>
      ((createBody()['initial_state'] ?? <Object?>[]) as List)
          .cast<Map<Object?, Object?>>()
          .where((event) => event['type'] == type);

  Future<void> create(WidgetTester tester) async {
    await harness.open(
      tester,
      path: Uri(pathSegments: ['rooms', 'space', _space]).toString(),
    );
    harness.client.rooms.add(
      Room(id: _newRoomId, client: harness.client, membership: Membership.join),
    );
    final l10n = L10n.of(tester.element(find.byType(SpaceOverview)));
    await tester.tap(find.byType(PopupMenuButton<void>));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.text(l10n.communityAddAnnouncements));
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.text(l10n.communityAddAnnouncements).last);
    await harness.settle(tester, rounds: 8);
  }

  testWidgets(
    'the room is created with moderator posting, encrypted, joinable from the space',
    (tester) async {
      await create(tester);
      final body = createBody();
      expect(
        (body['power_level_content_override'] as Map)['events_default'],
        50,
      );
      expect(initialState('m.room.encryption'), hasLength(1));
      final joinRules = initialState('m.room.join_rules');
      expect(joinRules, hasLength(1));
      final content = joinRules.single['content'] as Map;
      expect(content['join_rule'], 'restricted');
      expect(content['allow'], [
        {'type': 'm.room_membership', 'room_id': _space},
      ]);
      await harness.finish(tester);
    },
  );

  testWidgets(
    'it is added to the space as a suggested child with the own server',
    (tester) async {
      await create(tester);
      final puts = api.requests('/state/m.space.child/', method: 'PUT');
      expect(puts, hasLength(1));
      final body = puts.single.json! as Map;
      expect(body['suggested'], isTrue);
      expect(body['via'], ['fakeServer.notExisting']);
      expect(body['order'], matches(RegExp(r'^[\x20-\x7E]{1,50}$')));
      expect(puts.single.path, contains(_space));
      await harness.finish(tester);
    },
  );

  testWidgets('cancelling the dialog creates nothing', (tester) async {
    await harness.open(
      tester,
      path: Uri(pathSegments: ['rooms', 'space', _space]).toString(),
    );
    final l10n = L10n.of(tester.element(find.byType(SpaceOverview)));
    await tester.tap(find.byType(PopupMenuButton<void>));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.text(l10n.communityAddAnnouncements));
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.text(l10n.cancel));
    await harness.settle(tester, rounds: 3);
    expect(api.requests('/createRoom', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });
}
