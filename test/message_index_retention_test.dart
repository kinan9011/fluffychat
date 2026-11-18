// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/message_index.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

const _roomId = '!timer:example.org';
const _secret = 'SENTINEL-EXPIRED-BODY';

IndexedMessage _msg(int n, String text, DateTime at) => IndexedMessage(
  roomId: _roomId,
  eventId: '\$e$n:example.org',
  senderId: '@alice:example.org',
  timestamp: at.millisecondsSinceEpoch,
  kind: SearchKind.text,
  text: text,
);

void main() {
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
  });
  tearDownAll(() => client.dispose(closeDatabase: true));
  tearDown(() => MessageIndex.forget(client));

  test('the index of a client reads the timer of the room: what it hides is '
      'not written to the account database', () async {
    final room = searchRoom(client, _roomId);
    room.setState(
      Event(
        type: 'm.room.retention',
        stateKey: '',
        content: {
          'max_lifetime': const Duration(days: 1).inMilliseconds,
          'expire_on_clients': true,
        },
        room: room,
        eventId: r'$retention:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    client.rooms.add(room);
    final index = MessageIndex.of(client);
    await index.ready;
    index.add(
      _msg(1, _secret, DateTime.now().subtract(const Duration(days: 3))),
    );
    index.add(_msg(2, 'fresh words', DateTime.now()));
    await index.flush();
    final stored = jsonEncode(
      (await client.database.getCustomCacheObject(
        MessageIndex.documentKey,
      ))?.content,
    );
    expect(stored, contains('fresh words'));
    expect(stored, isNot(contains(_secret)));
    expect(index.length, 1);
  });
}
