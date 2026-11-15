// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/chat_list/archive_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/test_client.dart';

const _archived = {'im.fluffychat.archived': null};
const _user = '%40test%3AfakeServer.notExisting';

void main() {
  late Client client;
  late Client other;
  late FakeMatrixApi api;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
    api = FakeMatrixApi.currentApi!;
    FakeMatrixApi.client = client;
    other = await prepareTestClient(clientName: 'Policy other client');
    FakeMatrixApi.client = client;
    for (final id in ['ap1', 'ap2', 'ap3']) {
      api.api['DELETE']!['/client/v3/user/$_user/rooms/!$id%3Ax/tags/im.fluffychat.archived'] =
          (_) => {};
    }
  });

  setUp(() async {
    FakeMatrixApi.currentApi = api;
    FakeMatrixApi.calledEndpoints.clear();
    await AppSettings.unarchiveOnMention.setItem(true);
  });

  tearDown(() async {
    await AppSettings.unarchiveOnMention.setItem(false);
    client.rooms.removeWhere((room) => room.id.startsWith('!ap'));
  });

  Room room(
    String id, {
    Map<String, double?> tags = _archived,
    int highlight = 0,
    Membership membership = Membership.join,
  }) {
    final room = testChat(
      client,
      id,
      name: id,
      tags: tags,
      highlight: highlight,
      membership: membership,
    );
    client.rooms.add(room);
    return room;
  }

  SyncUpdate mention(String id, int count) => SyncUpdate(
    nextBatch: 'p',
    rooms: RoomsUpdate(
      join: {
        id: JoinedRoomUpdate(
          unreadNotifications: UnreadNotificationCounts(highlightCount: count),
        ),
      },
    ),
  );

  test('the setting is off by default and not settable from config.json', () {
    expect(AppSettings.unarchiveOnMention.defaultValue, isFalse);
    expect(webDeniedSettings, contains(AppSettings.unarchiveOnMention));
    expect(webAllowedSettings, isNot(contains(AppSettings.unarchiveOnMention)));
  });

  test('off: a mention in an archived chat changes nothing', () async {
    await AppSettings.unarchiveOnMention.setItem(false);
    room('!ap1:x');
    final policy = UnarchiveOnMention(client);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 3)), isEmpty);
    await policy.handle(mention('!ap1:x', 4));
    expect(
      FakeMatrixApi.calledEndpoints.keys.where((p) => p.contains('/tags/')),
      isEmpty,
    );
  });

  test('on: a new mention in an archived chat unarchives it', () {
    room('!ap1:x');
    expect(UnarchiveOnMention(client).roomsToUnarchive(mention('!ap1:x', 1)), [
      '!ap1:x',
    ]);
  });

  test('on: a chat that is not archived stays alone', () {
    room('!ap1:x', tags: const {});
    expect(
      UnarchiveOnMention(client).roomsToUnarchive(mention('!ap1:x', 1)),
      isEmpty,
    );
  });

  test('on: a count of zero is no mention', () {
    room('!ap1:x');
    expect(
      UnarchiveOnMention(client).roomsToUnarchive(mention('!ap1:x', 0)),
      isEmpty,
    );
  });

  test('on: a mention that was already there is not new', () {
    room('!ap1:x', highlight: 2);
    final policy = UnarchiveOnMention(client);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 2)), isEmpty);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 3)), ['!ap1:x']);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 3)), isEmpty);
  });

  test('a room seen for the first time only records its count', () {
    final policy = UnarchiveOnMention(client);
    room('!ap1:x');
    expect(policy.roomsToUnarchive(mention('!ap1:x', 2)), isEmpty);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 2)), isEmpty);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 3)), ['!ap1:x']);
  });

  test('an account added later does not unarchive on its first sync', () {
    final policy = UnarchiveOnMention(other);
    other.rooms.add(testChat(other, '!ap2:x', name: 'ap2', tags: _archived));
    addTearDown(() => other.rooms.removeWhere((room) => room.id == '!ap2:x'));
    expect(policy.roomsToUnarchive(mention('!ap2:x', 4)), isEmpty);
    expect(policy.roomsToUnarchive(mention('!ap2:x', 5)), ['!ap2:x']);
  });

  test('mentions seen while the setting was off never count later', () async {
    await AppSettings.unarchiveOnMention.setItem(false);
    room('!ap1:x');
    final policy = UnarchiveOnMention(client);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 2)), isEmpty);
    await AppSettings.unarchiveOnMention.setItem(true);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 2)), isEmpty);
    expect(policy.roomsToUnarchive(mention('!ap1:x', 3)), ['!ap1:x']);
  });

  test('an invite that kept the tag is not touched', () {
    room('!ap1:x', membership: Membership.invite);
    expect(
      UnarchiveOnMention(client).roomsToUnarchive(mention('!ap1:x', 1)),
      isEmpty,
    );
  });

  test('another account is never touched', () {
    room('!ap1:x');
    expect(
      UnarchiveOnMention(other).roomsToUnarchive(mention('!ap1:x', 1)),
      isEmpty,
    );
  });

  test('handle removes the tag of exactly the mentioned room', () async {
    room('!ap1:x');
    room('!ap2:x');
    final policy = UnarchiveOnMention(client);
    await policy.handle(mention('!ap1:x', 1));
    expect(
      FakeMatrixApi.calledEndpoints.keys.where((p) => p.contains('/tags/')),
      ['/client/v3/user/$_user/rooms/!ap1%3Ax/tags/im.fluffychat.archived'],
    );
  });

  test('a failing request is swallowed and logged without the room id', () async {
    room('!ap3:x');
    api.api['DELETE']!['/client/v3/user/$_user/rooms/!ap3%3Ax/tags/im.fluffychat.archived'] =
        (_) => throw Exception('offline');
    Logs().outputEvents.clear();
    await UnarchiveOnMention(client).handle(mention('!ap3:x', 1));
    final lines = Logs().outputEvents.where(
      (e) => e.title.contains('[Unarchive]'),
    );
    expect(lines.single.title, '[Unarchive] failed');
    for (final event in Logs().outputEvents) {
      expect('${event.title}${event.exception}', isNot(contains('!ap3')));
    }
    api.api['DELETE']!['/client/v3/user/$_user/rooms/!ap3%3Ax/tags/im.fluffychat.archived'] =
        (_) => {};
  });
}
