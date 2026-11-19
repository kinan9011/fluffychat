// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/search/chat_matcher.dart';
import 'package:odango/utils/search/search_query.dart';

import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  final names = <String, String>{};

  setUpAll(() async {
    client = await prepareTestClient();
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  String nameOf(Room room) => names[room.id] ?? room.id;

  Room room(String id, String name, {Membership membership = Membership.join}) {
    names[id] = name;
    return searchRoom(client, id, membership: membership);
  }

  List<String> run(List<Room> rooms, String query, {int limit = 30}) =>
      ChatMatcher.run(
        rooms,
        SearchQuery.parse(query),
        nameOf: nameOf,
        limit: limit,
      ).map((m) => names[m.room.id]!).toList();

  test('every word has to be in the name', () {
    final rooms = [
      room('!a:example.org', 'Design crew'),
      room('!b:example.org', 'Design team'),
      room('!c:example.org', 'Dev crew'),
    ];
    expect(run(rooms, 'design crew'), ['Design crew']);
    expect(run(rooms, 'CREW').toSet(), {'Design crew', 'Dev crew'});
  });

  test('only joined chats are listed', () {
    final rooms = [
      room('!a:example.org', 'Alpha'),
      room('!b:example.org', 'Alpha invite', membership: Membership.invite),
      room('!c:example.org', 'Alpha left', membership: Membership.leave),
    ];
    expect(run(rooms, 'alpha'), ['Alpha']);
  });

  test('an empty query lists the chats that were active last', () {
    final rooms = [
      room('!a:example.org', 'One'),
      room('!b:example.org', 'Two'),
    ];
    expect(run(rooms, '').toSet(), {'One', 'Two'});
  });

  test('the list is capped', () {
    final rooms = [
      for (var n = 0; n < 50; n++) room('!r$n:example.org', 'Room $n'),
    ];
    expect(run(rooms, 'room').length, ChatMatcher.defaultLimit);
    expect(run(rooms, 'room', limit: 5).length, 5);
  });

  test('archived chats are listed and flagged', () {
    final archived = room('!a:example.org', 'Old project');
    archived.roomAccountData['m.tag'] = BasicEvent(
      type: 'm.tag',
      content: {
        'tags': {'com.swovo.odango.archived': <String, Object?>{}},
      },
    );
    final matches = ChatMatcher.run(
      [archived, room('!b:example.org', 'New project')],
      SearchQuery.parse('project'),
      nameOf: nameOf,
    );
    expect(
      {for (final m in matches) names[m.room.id]!: m.archived},
      {'Old project': true, 'New project': false},
    );
  });
}
