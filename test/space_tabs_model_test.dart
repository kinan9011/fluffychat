// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/space_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  String nameOf(Room room) => room.id;

  SpaceTabsModel build(Iterable<Room> rooms) =>
      SpaceTabsModel.build(rooms, nameOf: nameOf);

  Room space(String id, List<String> children) =>
      testSpace(client, children, id: id);

  Room room(
    String id, {
    int unread = 0,
    Membership? membership,
    List<String> tags = const [],
  }) => testSpaceChild(
    client,
    id,
    unread: unread,
    membership: membership,
    tags: tags,
  );

  test('two top-level spaces and a subspace give two tabs', () {
    final model = build([
      space('!a:x', ['!sub:x', '!r1:x']),
      space('!sub:x', ['!r2:x']),
      space('!b:x', ['!r3:x']),
      room('!r1:x'),
      room('!r2:x'),
      room('!r3:x'),
    ]);
    expect(model.tabs.map((t) => t.spaceId), ['!a:x', '!b:x']);
    expect(model.roomsBySpace['!a:x'], {'!r1:x', '!r2:x'});
    expect(model.roomsBySpace['!b:x'], {'!r3:x'});
    expect(model.roomsInAnySpace, {'!r1:x', '!r2:x', '!r3:x'});
  });

  test('unread counts unread and invited rooms, not read ones', () {
    final model = build([
      space('!a:x', ['!r1:x', '!r2:x', '!r3:x', '!r4:x']),
      room('!r1:x', unread: 2),
      room('!r2:x', unread: 1),
      room('!r3:x', membership: Membership.invite),
      room('!r4:x'),
    ]);
    expect(model.tabs.single.unread, 3);
  });

  test('archived chats do not count towards a space tab', () {
    final model = build([
      space('!a:x', ['!r1:x', '!r2:x', '!r3:x']),
      room('!r1:x', unread: 2),
      room('!r2:x', unread: 5, tags: [archivedTag]),
      room('!r3:x', membership: Membership.invite, tags: [archivedTag]),
    ]);
    expect(model.tabs.single.unread, 2);
  });

  test('a cycle terminates and keeps both tabs', () {
    final logsBefore = Logs().outputEvents.length;
    final model = build([
      space('!a:x', ['!b:x', '!r1:x']),
      space('!b:x', ['!a:x', '!r2:x']),
      room('!r1:x'),
      room('!r2:x'),
    ]);
    expect(model.tabs.map((t) => t.spaceId), ['!a:x', '!b:x']);
    expect(model.roomsBySpace['!a:x'], {'!r1:x', '!r2:x'});
    expect(model.roomsBySpace['!b:x'], {'!r1:x', '!r2:x'});
    expect(
      Logs().outputEvents.skip(logsBefore).map((event) => event.title),
      isNot(contains('[SpaceTabs] hierarchy truncated')),
      reason: 'the cycle must end through the visited set, not the visit cap',
    );
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('a cycle is walked once, not once per lap (visited set)', () {
    final logsBefore = Logs().outputEvents.length;
    final bulk = [
      for (var i = 0; i < SpaceTabsModel.maxVisited ~/ 3; i++) '!c$i:x',
    ];
    final model = build([
      space('!a:x', ['!b:x', ...bulk]),
      space('!b:x', ['!a:x', '!r2:x']),
      room('!r2:x'),
    ]);
    expect(model.roomsBySpace['!b:x'], contains('!r2:x'));
    expect(model.roomsBySpace['!b:x'], contains('!c0:x'));
    expect(
      Logs().outputEvents.skip(logsBefore).map((event) => event.title),
      isNot(contains('[SpaceTabs] hierarchy truncated')),
    );
  });

  test('a cycle next to a normal space does not hide the cycle', () {
    final model = build([
      space('!a:x', ['!b:x']),
      space('!b:x', ['!a:x']),
      space('!c:x', []),
    ]);
    expect(model.tabs.map((t) => t.spaceId), ['!a:x', '!b:x', '!c:x']);
  });

  test('a subspace of a cycle does not become a tab of its own', () {
    final model = build([
      space('!a:x', ['!b:x', '!c:x']),
      space('!b:x', ['!a:x']),
      space('!c:x', ['!r:x']),
      room('!r:x'),
    ]);
    expect(model.tabs.map((t) => t.spaceId), ['!a:x', '!b:x']);
    expect(model.roomsBySpace['!a:x'], {'!r:x'});
  });

  test('a deep chain stops at the depth cap without throwing', () {
    final rooms = <Room>[];
    for (var i = 0; i < 20; i++) {
      rooms.add(space('!s$i:x', [if (i < 19) '!s${i + 1}:x', '!r$i:x']));
      rooms.add(room('!r$i:x'));
    }
    final model = build(rooms);
    expect(model.tabs.single.spaceId, '!s0:x');
    final members = model.roomsBySpace['!s0:x']!;
    expect(members, contains('!r${SpaceTabsModel.maxDepth}:x'));
    expect(members, isNot(contains('!r${SpaceTabsModel.maxDepth + 1}:x')));
  });

  test('spaces below the depth cap are not walked, so they cost no budget', () {
    final logsBefore = Logs().outputEvents.length;
    final chain = [
      for (var i = 0; i <= SpaceTabsModel.maxDepth + 1; i++)
        space('!s$i:x', [
          if (i <= SpaceTabsModel.maxDepth) '!s${i + 1}:x',
          if (i == SpaceTabsModel.maxDepth + 1)
            for (var j = 0; j < SpaceTabsModel.maxVisited + 1; j++) '!c$j:x',
        ]),
    ];
    final model = build([
      ...chain,
      space('!zz:x', ['!late:x']),
      room('!late:x'),
    ]);
    expect(model.tabs.map((t) => t.spaceId), ['!s0:x', '!zz:x']);
    expect(model.roomsBySpace['!zz:x'], {'!late:x'});
    expect(model.roomsBySpace['!s0:x'], isNot(contains('!c0:x')));
    expect(
      Logs().outputEvents.skip(logsBefore).map((event) => event.title),
      isNot(contains('[SpaceTabs] hierarchy truncated')),
    );
  });

  test('one huge space cannot starve the other spaces (L2)', () {
    final huge = [
      for (var i = 0; i < SpaceTabsModel.maxVisited + 500; i++) '!c$i:x',
    ];
    final model = build([
      space('!a-huge:x', huge),
      space('!b:x', ['!r1:x']),
      space('!c:x', ['!r2:x']),
      room('!r1:x'),
      room('!r2:x'),
    ]);
    expect(model.tabs.map((t) => t.spaceId), ['!a-huge:x', '!b:x', '!c:x']);
    expect(model.roomsBySpace['!b:x'], {'!r1:x'});
    expect(model.roomsBySpace['!c:x'], {'!r2:x'});
    expect(model.roomsInAnySpace, containsAll(['!r1:x', '!r2:x']));
  });

  test('a child we are not in is listed but not counted', () {
    final model = build([
      space('!a:x', ['!unknown:x', '!r1:x']),
      room('!r1:x', unread: 1),
    ]);
    expect(model.tabs.single.unread, 1);
    expect(model.roomsBySpace['!a:x'], contains('!unknown:x'));
  });

  test('tabs are sorted by lowercase name, then id', () {
    final model = SpaceTabsModel.build(
      [space('!b:x', []), space('!a:x', []), space('!c:x', [])],
      nameOf: (r) => switch (r.id) {
        '!a:x' => 'banana',
        '!b:x' => 'Apple',
        _ => 'banana',
      },
    );
    expect(model.tabs.map((t) => t.spaceId), ['!b:x', '!a:x', '!c:x']);
  });

  test('no joined space gives no tabs', () {
    expect(build([room('!r:x')]).tabs, isEmpty);
    expect(
      build([
        testSpace(client, [], id: '!i:x', membership: Membership.invite),
      ]).tabs,
      isEmpty,
    );
  });

  test('5000 rooms with a 500 room space build fast', () {
    final children = [for (var i = 0; i < 500; i++) '!c$i:x'];
    final rooms = <Room>[
      for (var i = 0; i < 50; i++)
        space('!s$i:x', i == 0 ? children : ['!c${i + 1000}:x']),
      for (var i = 0; i < 5000; i++) room('!c$i:x', unread: i % 3),
    ];
    final watch = Stopwatch()..start();
    final model = build(rooms);
    watch.stop();
    expect(model.tabs, hasLength(50));
    expect(watch.elapsedMilliseconds, lessThan(200));
  });

  test('a hostile hierarchy is cut at the visit cap', () {
    final children = [
      for (var i = 0; i < SpaceTabsModel.maxVisited + 500; i++) '!c$i:x',
    ];
    final model = build([space('!s:x', children)]);
    expect(
      model.roomsBySpace['!s:x']!.length,
      lessThanOrEqualTo(SpaceTabsModel.maxVisited),
    );
    expect(model.tabs, hasLength(1));
  });
}
