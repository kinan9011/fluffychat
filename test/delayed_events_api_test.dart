// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/scheduling/delayed_events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

typedef Seen = ({String method, Uri url, Object? body});

class _Server extends http.BaseClient {
  _Server(this.respond);

  final (int, Object?) Function(Seen request) respond;
  final inner = FakeMatrixApi();
  final seen = <Seen>[];

  Iterable<Seen> get delayed => seen.where(
    (r) => r.url.path.contains('msc4140') || r.url.path.contains('/send/'),
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (!path.contains('msc4140') && !path.contains('/send/')) {
      return inner.send(request);
    }
    final text = request is http.Request ? request.body : '';
    final record = (
      method: request.method,
      url: request.url,
      body: text.isEmpty ? null : jsonDecode(text),
    );
    seen.add(record);
    final (status, body) = respond(record);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

const roomId = '!api:example.org';

Map<String, Object?> item({
  String delayId = 'delay-1',
  String room = roomId,
  String type = 'm.room.message',
  Object? stateKey,
  Object? delay = 60000,
  Object? runningSince = 1700000000000,
  Object? content = const {'msgtype': 'm.text', 'body': 'hello'},
}) => {
  'delay_id': delayId,
  'room_id': room,
  'type': type,
  'state_key': ?stateKey,
  'delay': delay,
  'running_since': runningSince,
  'content': content,
};

void main() {
  late Client client;
  late Room room;
  late _Server server;
  late (int, Object?) Function(Seen) handler;

  Future<void> open({bool encrypted = false}) async {
    server = _Server((r) => handler(r));
    client = await prepareTestClient(httpClient: server);
    room = Room(id: roomId, client: client);
    if (encrypted) {
      room.setState(
        Event(
          type: EventTypes.Encryption,
          stateKey: '',
          content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
          room: room,
          eventId: r'$enc:example.org',
          senderId: '@test:fakeServer.notExisting',
          originServerTs: DateTime(2025),
        ),
      );
    }
  }

  setUp(() {
    handler = (_) => (200, {'delay_id': 'delay-1'});
  });

  DelayedEventsApi api({
    bool encryptionReady = true,
    Map<String, Object?> Function(Map<String, Object?>)? encrypt,
  }) => DelayedEventsApi(
    client,
    encryptionReady: () => encryptionReady,
    encrypt: (roomId, content) async =>
        encrypt?.call(content) ?? {'ciphertext': 'x', 'algorithm': 'a'},
  );

  group('scheduleMessage', () {
    test('a plain room gets one PUT with the delay and the content', () async {
      await open();
      final id = await api().scheduleMessage(room, {
        'msgtype': 'm.text',
        'body': 'hello',
      }, const Duration(minutes: 5));
      expect(id, 'delay-1');
      final request = server.delayed.single;
      expect(request.method, 'PUT');
      expect(
        request.url.path,
        startsWith(
          '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/',
        ),
      );
      expect(request.url.queryParameters, {
        'org.matrix.msc4140.delay': '300000',
      });
      expect(request.body, {'msgtype': 'm.text', 'body': 'hello'});
    });

    test('less than a minute is refused before any request', () async {
      await open();
      await expectLater(
        api().scheduleMessage(room, {
          'msgtype': 'm.text',
          'body': 'x',
        }, const Duration(seconds: 59)),
        throwsA(isA<ScheduleDelayTooShort>()),
      );
      expect(server.delayed, isEmpty);
    });

    test(
      'a bad delay id in the answer is refused without echoing it',
      () async {
        await open();
        for (final bad in <Object?>['has space', '../x', 5, null, '']) {
          handler = (_) => (200, {'delay_id': bad});
          Object? thrown;
          try {
            await api().scheduleMessage(room, {
              'msgtype': 'm.text',
              'body': 'x',
            }, const Duration(minutes: 5));
          } catch (e) {
            thrown = e;
          }
          expect(thrown, isA<FormatException>(), reason: '$bad');
          expect(thrown.toString(), isNot(contains('has space')));
        }
      },
    );

    test('an encrypted room without encryption sends nothing', () async {
      await open(encrypted: true);
      await expectLater(
        api(encryptionReady: false).scheduleMessage(room, {
          'msgtype': 'm.text',
          'body': 'SENTINEL-PLAIN-5',
        }, const Duration(minutes: 5)),
        throwsA(isA<ScheduledEncryptionUnavailable>()),
      );
      expect(server.delayed, isEmpty);
    });

    test('an encrypted room sends ciphertext, never the text', () async {
      await open(encrypted: true);
      await api().scheduleMessage(room, {
        'msgtype': 'm.text',
        'body': 'SENTINEL-PLAIN-6',
      }, const Duration(minutes: 5));
      final request = server.delayed.single;
      expect(request.url.path, contains('/send/m.room.encrypted/'));
      expect(request.body, {'ciphertext': 'x', 'algorithm': 'a'});
      expect(jsonEncode(request.body), isNot(contains('SENTINEL')));
    });

    test('a real encrypting client sends ciphertext and no body', () async {
      await open(encrypted: true);
      client.rooms.add(room);
      await DelayedEventsApi(client).scheduleMessage(room, {
        'msgtype': 'm.text',
        'body': 'SENTINEL-PLAIN-REAL',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$reply:example.org'},
        },
      }, const Duration(minutes: 5));
      final request = server.delayed.single;
      expect(request.url.path, contains('/send/m.room.encrypted/'));
      final body = request.body! as Map<String, Object?>;
      expect(body['algorithm'], AlgorithmTypes.megolmV1AesSha2);
      expect(body['ciphertext'], isA<String>());
      expect(body['session_id'], isA<String>());
      expect(body.containsKey('body'), isFalse);
      expect(body.containsKey('msgtype'), isFalse);
      expect(jsonEncode(body), isNot(contains('SENTINEL')));
    });

    test('plaintext coming back from encryption is never sent', () async {
      await open(encrypted: true);
      await expectLater(
        api(encrypt: (content) => content).scheduleMessage(room, {
          'msgtype': 'm.text',
          'body': 'SENTINEL-PLAIN-7',
        }, const Duration(minutes: 5)),
        throwsA(isA<ScheduledEncryptionUnavailable>()),
      );
      expect(server.delayed, isEmpty);
    });
  });

  group('list', () {
    test('reads the Synapse endpoint and computes the send time', () async {
      await open();
      handler = (r) => (
        200,
        {
          'delayed_events': [item()],
        },
      );
      final result = await api().list();
      expect(result.complete, isTrue);
      final events = result.events;
      expect(events.single.delayId, 'delay-1');
      expect(
        events.single.sendAt,
        DateTime.fromMillisecondsSinceEpoch(1700000060000),
      );
      expect(events.single.content['body'], 'hello');
      expect(
        server.delayed.single.url.path,
        endsWith('/org.matrix.msc4140/delayed_events'),
      );
    });

    test('falls back to the spec endpoint and its key', () async {
      await open();
      handler = (r) => r.url.path.endsWith('/scheduled')
          ? (
              200,
              {
                'scheduled': [item()],
              },
            )
          : (404, {'errcode': 'M_UNRECOGNIZED', 'error': 'nope'});
      final events = (await api().list()).events;
      expect(events, hasLength(1));
      expect(server.delayed.map((r) => r.url.path.split('/').last), [
        'delayed_events',
        'scheduled',
      ]);
    });

    test('follows next_batch but stops after five pages', () async {
      await open();
      handler = (r) => (
        200,
        {
          'delayed_events': [item(delayId: 'd${server.seen.length}')],
          'next_batch': 'more',
        },
      );
      final result = await api().list();
      expect(server.delayed, hasLength(DelayedEventsApi.maxPages));
      expect(result.events, hasLength(DelayedEventsApi.maxPages));
      expect(result.complete, isFalse);
    });

    test('keeps at most 500 entries', () async {
      await open();
      handler = (r) => (
        200,
        {
          'delayed_events': [
            for (var i = 0; i < 300; i++)
              item(delayId: 'd${server.seen.length}-$i'),
          ],
          'next_batch': 'more',
        },
      );
      final result = await api().list();
      expect(result.events, hasLength(DelayedEventsApi.maxEntries));
      expect(result.complete, isFalse);
    });

    test('state events and foreign types are never listed', () async {
      await open();
      handler = (r) => (
        200,
        {
          'delayed_events': [
            item(
              delayId: 'rtc-leave',
              type: 'org.matrix.msc3401.call.member',
              stateKey: '_@a:b_dev',
            ),
            item(delayId: 'state-empty', type: 'm.room.message', stateKey: ''),
            item(delayId: 'topic', type: 'm.room.topic'),
            item(delayId: 'plain'),
            item(
              delayId: 'cipher',
              type: 'm.room.encrypted',
              content: {'ciphertext': 'x'},
            ),
          ],
        },
      );
      expect((await api().list()).events.map((e) => e.delayId), [
        'plain',
        'cipher',
      ]);
    });

    test('odd entries are skipped one by one', () async {
      await open();
      handler = (r) => (
        200,
        {
          'delayed_events': [
            item(delayId: 'good'),
            'text',
            null,
            item(delayId: 'bad/id'),
            item(delayId: 'delay-neg', delay: -1),
            item(delayId: 'delay-str', delay: '5'),
            item(delayId: 'delay-big', delay: 400 * 86400000 + 1),
            item(delayId: 'since-neg', runningSince: -5),
            item(delayId: 'content-no', content: 'nope'),
            item(delayId: 'content-big', content: {'body': 'a' * 100001}),
            item(delayId: 'room-bad', room: 'room'),
          ],
        },
      );
      expect((await api().list()).events.map((e) => e.delayId), ['good']);
    });

    test('a hostile answer is not a list', () async {
      await open();
      handler = (r) => (200, {'delayed_events': 'nope'});
      expect((await api().list()).events, isEmpty);
    });
  });

  group('manage', () {
    test('send now and cancel post their action to the id', () async {
      await open();
      handler = (r) => (200, <String, Object?>{});
      await api().sendNow('delay-1');
      await api().cancel('delay-1');
      expect(server.delayed.map((r) => r.method), ['POST', 'POST']);
      expect(server.delayed.map((r) => r.body), [
        {'action': 'send'},
        {'action': 'cancel'},
      ]);
      expect(
        server.delayed.every((r) => r.url.path.endsWith('/delay-1')),
        isTrue,
      );
    });

    test('a bad id never reaches the network', () async {
      await open();
      for (final bad in ['../x', 'a/b', '..', '', 'a?b']) {
        await expectLater(api().cancel(bad), throwsA(isA<FormatException>()));
        await expectLater(api().sendNow(bad), throwsA(isA<FormatException>()));
      }
      expect(server.delayed, isEmpty);
    });
  });

  group('secrets', () {
    test('the id is in no log line and no thrown text', () async {
      await open();
      const sentinel = 'SENTINEL-DELAY-ID-9z';
      handler = (r) => (500, {'error': 'boom'});
      Logs().outputEvents.clear();
      final thrown = <Object>[];
      for (final action in <Future<Object?> Function()>[
        () => api().cancel(sentinel),
        () => api().sendNow(sentinel),
        () => api().list(),
        () => api().scheduleMessage(room, {
          'msgtype': 'm.text',
          'body': 'x',
        }, const Duration(minutes: 5)),
      ]) {
        try {
          await action();
        } catch (e) {
          thrown.add(e);
        }
      }
      expect(thrown, hasLength(4));
      for (final e in thrown) {
        expect(e.toString(), isNot(contains(sentinel)));
      }
      for (final event in Logs().outputEvents) {
        expect(event.title, isNot(contains(sentinel)));
        expect('${event.exception}', isNot(contains(sentinel)));
      }
      expect(
        Logs().outputEvents.where((e) => e.title.contains('[Scheduled]')),
        isNotEmpty,
      );
    });
  });
}
