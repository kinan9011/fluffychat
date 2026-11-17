// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/export/export_json.dart';
import 'package:fluffychat/utils/export/export_model.dart';
import 'package:flutter_test/flutter_test.dart';

ExportEvent _event(Map<String, Object?> content) => ExportEvent(
  eventId: r'$e1',
  senderId: '@alice:example.org',
  senderName: 'Alice',
  time: DateTime.utc(2030, 5, 10, 12),
  type: 'm.room.message',
  text: 'x',
  content: content,
);

class _PoisonEvent extends ExportEvent {
  _PoisonEvent()
    : super(
        eventId: r'$p',
        senderId: '@a:b',
        senderName: 'A',
        time: DateTime.utc(2030),
        type: 'm.room.message',
        text: '',
        content: const {},
      );

  @override
  Map<String, Object?> get content => throw StateError('read after the limit');
}

final _meta = ExportMeta(
  roomId: '!room:example.org',
  roomName: 'Room',
  encrypted: true,
  exportedAt: DateTime.utc(2030, 5, 11),
);

void main() {
  group('scrubContent', () {
    test('removes the decryption secrets of an attachment', () {
      final out = scrubContent({
        'msgtype': 'm.image',
        'body': 'a.png',
        'file': {
          'url': 'mxc://example.org/abc',
          'key': {'k': 'SECRETKEYVALUE', 'alg': 'A256CTR'},
          'iv': 'SECRETIV',
          'hashes': {'sha256': 'SECRETHASH'},
          'v': 'v2',
        },
        'info': {
          'thumbnail_file': {
            'url': 'mxc://example.org/thumb',
            'key': {'k': 'THUMBSECRET'},
            'iv': 'THUMBIV',
            'hashes': {'sha256': 'THUMBHASH'},
          },
        },
      });
      final text = jsonEncode(out);
      for (final secret in [
        'SECRETKEYVALUE',
        'SECRETIV',
        'SECRETHASH',
        'THUMBSECRET',
        'THUMBIV',
        'THUMBHASH',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(text, contains('mxc://example.org/abc'));
      expect(text, contains('mxc://example.org/thumb'));
    });

    test('keeps ordinary keys named key, iv or hashes outside a file', () {
      final out = scrubContent({'key': 'reaction', 'iv': 1});
      expect(out, {'key': 'reaction', 'iv': 1});
    });

    test('non string keys and odd values are dropped', () {
      final out = scrubContent({
        'a': 1,
        'b': double.nan,
        'c': Object(),
        'd': [1, 2],
        'e': {1: 'x', 'ok': true},
      });
      expect(out['a'], 1);
      expect(out['b'], isNull);
      expect(out['c'], isNull);
      expect(out['d'], [1, 2]);
      expect(out['e'], {'ok': true});
    });

    test('deep nesting is cut, not thrown', () {
      Object? nest(int depth) => depth == 0 ? 'leaf' : {'n': nest(depth - 1)};
      final out = scrubContent({'x': nest(50)});
      expect(jsonEncode(out), isNot(contains('leaf')));
    });

    test('a huge number of nodes is cut', () {
      final out = scrubContent({
        'list': [for (var i = 0; i < 20000; i++) i],
      });
      final list = out['list']! as List;
      expect(list.where((v) => v != null).length, lessThan(5001));
    });

    test('long strings are cut at the per message cap', () {
      final out = scrubContent({'body': 'x' * 200000});
      final body = out['body']! as String;
      expect(body.length, ExportLimits.maxTextPerMessage + 1);
    });
  });

  group('buildJson', () {
    test('has the fixed envelope', () {
      final json =
          jsonDecode(
                buildJson(_meta, [
                  _event({'body': 'hi'}),
                ]),
              )
              as Map;
      expect(json['format'], 'im.fluffychat.export');
      expect(json['version'], 1);
      expect(json['exported_at'], '2030-05-11T00:00:00.000Z');
      expect(json['truncated'], false);
      expect(json['room'], {
        'id': '!room:example.org',
        'name': 'Room',
        'encrypted': true,
      });
      final event = (json['events'] as List).single as Map;
      expect(event.keys.toSet(), {
        'event_id',
        'sender',
        'origin_server_ts',
        'type',
        'content',
      });
      expect(event['origin_server_ts'], 1904644800000);
    });

    test('only whitelisted event fields are written', () {
      final event = ExportEvent(
        eventId: r'$e1',
        senderId: '@a:b',
        senderName: 'A',
        time: DateTime.utc(2030),
        type: 'm.room.message',
        text: 't',
        content: const {
          'body': 'x',
          'unsigned': {'x': 1},
        },
      );
      final text = buildJson(_meta, [event]);
      expect(text, isNot(contains('device_id')));
      expect(text, isNot(contains('sender_key')));
      expect(text, isNot(contains('session_id')));
    });

    test('the text is the same as one pretty printed document', () {
      for (final count in [0, 1, 3]) {
        final events = [
          for (var i = 0; i < count; i++)
            _event({
              'body': 'hi $i',
              'nested': {
                'list': [1, 2, 3],
              },
            }),
        ];
        expect(
          buildJson(_meta, events),
          const JsonEncoder.withIndent('  ').convert({
            'format': 'im.fluffychat.export',
            'version': 1,
            'exported_at': '2030-05-11T00:00:00.000Z',
            'truncated': false,
            'room': {
              'id': '!room:example.org',
              'name': 'Room',
              'encrypted': true,
            },
            'events': [
              for (final event in events)
                {
                  'event_id': event.eventId,
                  'sender': event.senderId,
                  'origin_server_ts': event.time.millisecondsSinceEpoch,
                  'type': event.type,
                  'content': scrubContent(event.content),
                },
            ],
          }),
        );
      }
    });

    test('stops at the length limit without reading the rest', () {
      final events = [
        _event({'body': 'x' * 2000}),
        _event({'body': 'y' * 2000}),
        _PoisonEvent(),
      ];
      expect(
        () => buildJson(_meta, events, maxLength: 3000),
        throwsA(isA<ExportTooLarge>()),
      );
    });

    test('the output is valid json for an encrypted image', () {
      final text = buildJson(_meta, [
        _event({
          'msgtype': 'm.image',
          'file': {
            'url': 'mxc://x/y',
            'key': {'k': 'SECRETKEYVALUE'},
            'iv': 'IV',
            'hashes': {'sha256': 'H'},
          },
        }),
      ]);
      expect(() => jsonDecode(text), returnsNormally);
      expect(text, isNot(contains('SECRETKEYVALUE')));
    });
  });
}
