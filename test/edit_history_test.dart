// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show BaseClient, BaseRequest, StreamedResponse;
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/chat/edit_history.dart';

import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  var counter = 0;

  setUpAll(() async {
    client = await prepareTestClient();
    room = Room(id: '!history:example.org', client: client);
  });

  const alice = '@alice:example.org';

  Event original({String sender = alice}) => Event(
    type: EventTypes.Message,
    content: {'msgtype': 'm.text', 'body': 'first'},
    room: room,
    eventId: r'$original:example.org',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  Event edit(
    String body, {
    String sender = alice,
    String target = r'$original:example.org',
    String relType = 'm.replace',
    int ts = 2000,
    String? id,
    Map<String, Object?>? newContent,
    bool withNewContent = true,
  }) => Event(
    type: EventTypes.Message,
    content: {
      'msgtype': 'm.text',
      'body': '* $body',
      'm.relates_to': {'rel_type': relType, 'event_id': target},
      if (withNewContent)
        'm.new_content': newContent ?? {'msgtype': 'm.text', 'body': body},
    },
    room: room,
    eventId: id ?? '\$edit${counter++}:example.org',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
  );

  EditHistory? build(Iterable<Event> candidates, {Event? source}) =>
      buildEditHistory(
        original: source ?? original(),
        originalText: 'first',
        candidates: candidates,
      );

  test('no edits means no history', () {
    expect(build([]), isNull);
  });

  test('three edits are ordered by time with the original first', () {
    final history = build([
      edit('third', ts: 4000),
      edit('second', ts: 3000),
      edit('first edit', ts: 2000),
    ])!;
    expect(history.original.text, 'first');
    expect(history.edits.map((e) => e.text), ['first edit', 'second', 'third']);
    expect(history.edits.last.time, DateTime.fromMillisecondsSinceEpoch(4000));
  });

  test('edits from another sender are ignored', () {
    expect(build([edit('hijack', sender: '@mallory:example.org')]), isNull);
  });

  test(
    'edits of another event, another relation or without content are ignored',
    () {
      expect(build([edit('x', target: r'$other:example.org')]), isNull);
      expect(build([edit('x', relType: 'm.annotation')]), isNull);
      expect(build([edit('x', withNewContent: false)]), isNull);
      expect(
        build([
          edit('x', newContent: {'msgtype': 'm.text', 'body': 5}),
        ]),
        isNull,
      );
      expect(
        build([
          edit('x', newContent: {'msgtype': 'm.text', 'body': '  \n'}),
        ]),
        isNull,
      );
    },
  );

  test('a redacted edit is ignored', () {
    final redacted = edit('gone');
    redacted.setRedactionEvent(
      Event(
        type: EventTypes.Redaction,
        content: const {},
        room: room,
        eventId: r'$redaction:example.org',
        senderId: alice,
        originServerTs: DateTime.now(),
        redacts: redacted.eventId,
      ),
    );
    expect(build([redacted]), isNull);
  });

  test('the same event twice counts once', () {
    final history = build([
      edit('same', id: r'$dup:example.org'),
      edit('same', id: r'$dup:example.org'),
    ])!;
    expect(history.edits, hasLength(1));
  });

  test('only the newest 50 edits are kept', () {
    final history = build([
      for (var i = 0; i < 60; i++) edit('v$i', ts: 2000 + i),
    ])!;
    expect(history.edits, hasLength(RichLimits.maxEdits));
    expect(history.edits.first.text, 'v10');
    expect(history.edits.last.text, 'v59');
  });

  test('a huge body is cut to 16 000 characters', () {
    final history = build([edit('a' * 20000)])!;
    expect(history.edits.single.text.length, RichLimits.maxEditUnits);
  });

  test('equal timestamps are ordered by event id', () {
    final history = build([
      edit('b', ts: 5000, id: r'$b:example.org'),
      edit('a', ts: 5000, id: r'$a:example.org'),
    ])!;
    expect(history.edits.map((e) => e.text), ['a', 'b']);
  });

  group('fetchEditEvents', () {
    Future<(Room, _Relations)> relationsRoom(int status, Object? body) async {
      final http = _Relations(status, body);
      final client = await prepareTestClient(
        clientName: 'relations-${counter++}',
        httpClient: http,
      );
      return (Room(id: '!history:example.org', client: client), http);
    }

    Map<String, Object?> raw(String id, {String type = 'm.room.message'}) => {
      'type': type,
      'event_id': id,
      'sender': alice,
      'origin_server_ts': 2000,
      'room_id': '!history:example.org',
      'content': {
        'msgtype': 'm.text',
        'body': '* new',
        'm.new_content': {'msgtype': 'm.text', 'body': 'new'},
        'm.relates_to': {
          'rel_type': 'm.replace',
          'event_id': r'$original:example.org',
        },
      },
    };

    test('a failing homeserver gives no extra events', () async {
      final (room, _) = await relationsRoom(500, {'errcode': 'M_UNKNOWN'});
      expect(await fetchEditEvents(room, original()), isEmpty);
    });

    test(
      'one page, own homeserver, capped at 50, next page not followed',
      () async {
        final (room, http) = await relationsRoom(200, {
          'chunk': [for (var i = 0; i < 60; i++) raw('\$r$i:example.org')],
          'next_batch': 'more',
        });
        final events = await fetchEditEvents(room, original());
        expect(events, hasLength(RichLimits.maxEdits));
        expect(http.relationRequests, hasLength(1));
        final url = http.relationRequests.single;
        expect(url.origin, room.client.homeserver!.origin);
        expect(url.path, contains('/relations/'));
        expect(url.path, endsWith('/m.replace'));
        expect(url.queryParameters['limit'], '50');
        expect(url.queryParameters['dir'], 'b');
        expect(url.queryParameters.containsKey('from'), isFalse);
      },
    );

    test('garbage in the response gives nothing', () async {
      final (room, _) = await relationsRoom(200, {
        'chunk': ['not an event', 5],
      });
      expect(await fetchEditEvents(room, original()), isEmpty);
    });

    test(
      'an undecryptable result stays encrypted and never becomes history',
      () async {
        final (room, _) = await relationsRoom(200, {
          'chunk': [raw(r'$enc:example.org', type: 'm.room.encrypted')],
        });
        final events = await fetchEditEvents(room, original());
        expect(events.single.type, EventTypes.Encrypted);
        expect(build(events), isNull);
      },
    );

    test('hostile edits from the server are filtered by the history', () async {
      final hostile = raw(r'$h:example.org');
      hostile['sender'] = '@mallory:example.org';
      final (room, _) = await relationsRoom(200, {
        'chunk': [hostile, raw(r'$ok:example.org')],
      });
      final history = build(await fetchEditEvents(room, original()))!;
      expect(history.edits.map((e) => e.eventId), [r'$ok:example.org']);
    });
  });
}

class _Relations extends BaseClient {
  _Relations(this.status, this.body);

  final int status;
  final Object? body;
  final inner = FakeMatrixApi();
  final relationRequests = <Uri>[];

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (request.url.path.contains('/relations/')) {
      relationRequests.add(request.url);
      return StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    return inner.send(request);
  }
}
