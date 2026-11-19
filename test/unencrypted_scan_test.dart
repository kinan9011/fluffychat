// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/search/search_filter.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/utils/search/unencrypted_scan.dart';

import 'utils/recording_api.dart';
import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  final api = RecordingApi();
  final now = DateTime(2031, 6, 15, 12);
  var stored = <String, List<Event>>{};
  var reads = <String>[];
  const files = MessageSearchFilter(types: {SearchType.files});

  setUpAll(() async {
    client = await prepareTestClient(httpClient: api);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  setUp(() {
    client.rooms.clear();
    stored = {};
    reads = [];
    api.clear();
  });

  UnencryptedScan scan() => UnencryptedScan(
    client,
    now: () => now,
    reader: (room, limit) async {
      reads.add('${room.id}:$limit');
      return stored[room.id] ?? [];
    },
  );

  Event file(Room room, int n, {DateTime? at}) => searchEvent(
    room,
    '\$e$n:example.org',
    msgtype: MessageTypes.File,
    body: 'doc$n.pdf',
    at: at ?? now.subtract(const Duration(hours: 1)),
  );

  test('reads only unencrypted rooms and sends no request', () async {
    final open = searchRoom(client, '!open:example.org', encrypted: false);
    final secret = searchRoom(client, '!secret:example.org');
    client.rooms.addAll([open, secret]);
    stored[open.id] = [file(open, 1)];
    stored[secret.id] = [file(secret, 2)];
    final hits = await scan().run(files);
    expect(hits.single.message.eventId, r'$e1:example.org');
    expect(reads, ['!open:example.org:200']);
    expect(api.log, isEmpty);
  });

  test('an empty filter lists nothing', () async {
    final open = searchRoom(client, '!open:example.org', encrypted: false);
    client.rooms.add(open);
    stored[open.id] = [file(open, 1)];
    expect(await scan().run(MessageSearchFilter.none), isEmpty);
    expect(reads, isEmpty);
  });

  test('at most 20 rooms with 200 events each', () async {
    for (var n = 0; n < 30; n++) {
      final room = searchRoom(client, '!r$n:example.org', encrypted: false);
      client.rooms.add(room);
      stored[room.id] = [file(room, n)];
    }
    await scan().run(files);
    expect(reads.length, UnencryptedScan.maxRooms);
    expect(
      reads.every((r) => r.endsWith(':${UnencryptedScan.perRoom}')),
      isTrue,
    );
  });

  test('the in-filter limits the rooms', () async {
    final a = searchRoom(client, '!a:example.org', encrypted: false);
    final b = searchRoom(client, '!b:example.org', encrypted: false);
    client.rooms.addAll([a, b]);
    stored[a.id] = [file(a, 1)];
    stored[b.id] = [file(b, 2)];
    final hits = await scan().run(
      files.copyWith(inRoomIds: {'!b:example.org'}),
    );
    expect(hits.single.message.roomId, '!b:example.org');
  });

  test('the retention timer hides messages here too', () async {
    final open = searchRoom(client, '!open:example.org', encrypted: false);
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
    client.rooms.add(open);
    stored[open.id] = [
      file(open, 1, at: now.subtract(const Duration(days: 3))),
      file(open, 2),
    ];
    final hits = await scan().run(files);
    expect(hits.map((h) => h.message.eventId), [r'$e2:example.org']);
  });

  test('newest first and limited', () async {
    final open = searchRoom(client, '!open:example.org', encrypted: false);
    client.rooms.add(open);
    stored[open.id] = [
      for (var n = 1; n <= 10; n++)
        file(open, n, at: now.subtract(Duration(minutes: n))),
    ];
    final hits = await scan().run(files, limit: 3);
    expect(hits.map((h) => h.message.eventId), [
      r'$e1:example.org',
      r'$e2:example.org',
      r'$e3:example.org',
    ]);
  });

  test('a room that became encrypted while reading is skipped', () async {
    final open = searchRoom(client, '!open:example.org', encrypted: false);
    client.rooms.add(open);
    final s = UnencryptedScan(
      client,
      now: () => now,
      reader: (room, limit) async {
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
        return [file(open, 1)];
      },
    );
    expect(await s.run(files), isEmpty);
  });
}
