// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluffychat/utils/export/export_model.dart';
import 'package:fluffychat/utils/export/export_runner.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

class _Timeline implements ExportTimeline {
  _Timeline(this.events, {this.more = const []});

  @override
  final List<Event> events;
  final List<List<Event>> more;
  int loads = 0;
  void Function()? onLoad;
  final edits = <String, Event>{};
  var stuck = false;

  @override
  bool get canLoadMore => stuck || loads < more.length;

  @override
  Future<void> loadMore() async {
    onLoad?.call();
    if (stuck) return;
    events.addAll(more[loads++]);
  }

  @override
  Event display(Event event) => edits[event.eventId] ?? event;

  int disposed = 0;

  @override
  void dispose() => disposed++;
}

const _texts = ChatExportTexts(
  undecryptable: '[cannot decrypt]',
  truncated: 'stopped at the limit',
  mediaSkipped: 'some media skipped',
);

void main() {
  late Client client;
  late Room room;
  final base = DateTime.utc(2030, 5, 10, 12);

  setUpAll(() async {
    client = await prepareTestClient();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
  });

  Event event(
    String id,
    String body, {
    int minutes = 0,
    String type = 'm.room.message',
    Map<String, Object?>? content,
    Map<String, Object?>? unsigned,
    String sender = '@alice:example.org',
  }) => Event(
    type: type,
    content: content ?? {'msgtype': 'm.text', 'body': body},
    room: room,
    eventId: id,
    senderId: sender,
    originServerTs: base.add(Duration(minutes: minutes)),
    unsigned: unsigned,
  );

  ChatExportRunner runner(
    _Timeline timeline, {
    RetentionPolicy? retention,
    MediaDownloader? download,
    int maxEvents = ExportLimits.maxEvents,
    Duration maxDuration = ExportLimits.maxDuration,
    DateTime Function()? now,
    String name = 'Design crew',
    bool encrypted = false,
  }) => ChatExportRunner(
    timeline: timeline,
    roomId: room.id,
    roomName: name,
    encrypted: encrypted,
    texts: _texts,
    retention: retention,
    maxEvents: maxEvents,
    maxDuration: maxDuration,
    now: now ?? () => base.add(const Duration(days: 1)),
    downloadMedia: download ?? (_) async => null,
  );

  const html = ExportOptions(format: ExportFormat.html);
  const jsonOptions = ExportOptions(format: ExportFormat.json);

  String text(ChatExportResult result) => utf8.decode(result.bytes);

  test('events come out oldest first', () async {
    final result = await runner(
      _Timeline([
        event(r'$3', 'third', minutes: 3),
        event(r'$1', 'first', minutes: 1),
        event(r'$2', 'second', minutes: 2),
      ]),
    ).run(html);
    final out = text(result);
    expect(out.indexOf('first'), lessThan(out.indexOf('second')));
    expect(out.indexOf('second'), lessThan(out.indexOf('third')));
    expect(result.eventCount, 3);
    expect(result.fileName, 'export-Design_crew-20300511.html');
    expect(result.mimeType, 'text/html');
  });

  test('an edit shows its new text and the edit event is not listed', () async {
    final original = event(r'$1', 'old text', minutes: 1);
    final edit = event(
      r'$e',
      '* new text',
      minutes: 2,
      content: {
        'msgtype': 'm.text',
        'body': '* new text',
        'm.new_content': {'msgtype': 'm.text', 'body': 'new text'},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$1'},
      },
    );
    final timeline = _Timeline([original, edit]);
    timeline.edits[r'$1'] = event(r'$1', 'new text', minutes: 1);
    final result = await runner(timeline).run(html);
    final out = text(result);
    expect(out, contains('new text'));
    expect(out, isNot(contains('old text')));
    expect(out, isNot(contains('* new text')));
    expect(result.eventCount, 1);
  });

  test('only body is exported, never formatted_body', () async {
    final result = await runner(
      _Timeline([
        event(
          r'$1',
          'plain words',
          content: {
            'msgtype': 'm.text',
            'body': 'plain words',
            'format': 'org.matrix.custom.html',
            'formatted_body': '<b>FORMATTED</b><script>x</script>',
          },
        ),
      ]),
    ).run(html);
    final out = text(result);
    expect(out, contains('plain words'));
    expect(out, isNot(contains('FORMATTED')));
    expect(out, isNot(contains('<script>')));
  });

  test('a redacted event is skipped', () async {
    final redacted = event(
      r'$r',
      'secret',
      unsigned: {
        'redacted_because': {
          'type': 'm.room.redaction',
          'event_id': r'$red',
          'sender': '@alice:example.org',
          'origin_server_ts': 1,
          'content': <String, Object?>{},
        },
      },
    );
    final result = await runner(
      _Timeline([redacted, event(r'$1', 'kept')]),
    ).run(html);
    expect(text(result), isNot(contains('secret')));
    expect(result.eventCount, 1);
  });

  test(
    'a message that could not be decrypted gets a placeholder only',
    () async {
      final result = await runner(
        _Timeline([
          event(
            r'$u',
            '',
            type: 'm.room.encrypted',
            content: {
              'algorithm': 'm.megolm.v1.aes-sha2',
              'ciphertext': 'CIPHERTEXTSECRET',
              'session_id': 'SESSIONSECRET',
            },
          ),
        ]),
        encrypted: true,
      ).run(jsonOptions);
      final out = text(result);
      expect(out, isNot(contains('CIPHERTEXTSECRET')));
      expect(out, isNot(contains('SESSIONSECRET')));
      final json = jsonDecode(out) as Map;
      expect(json['room'], containsPair('encrypted', true));
    },
  );

  test('state events are not exported', () async {
    final result = await runner(
      _Timeline([
        event(
          r'$s',
          '',
          type: 'm.room.member',
          content: {'membership': 'join'},
        ),
        event(r'$1', 'hello'),
      ]),
    ).run(html);
    expect(result.eventCount, 1);
  });

  group('disappearing messages', () {
    Event old() => event(r'$old', 'too old', minutes: 0);
    Event fresh() => event(r'$new', 'still visible', minutes: 60 * 20);

    test('hidden messages are not exported when the timer is on', () async {
      final result = await runner(
        _Timeline([old(), fresh()]),
        retention: const RetentionPolicy(Duration(hours: 12)),
      ).run(html);
      expect(text(result), isNot(contains('too old')));
      expect(text(result), contains('still visible'));
    });

    test('everything is exported when there is no timer', () async {
      final result = await runner(_Timeline([old(), fresh()])).run(html);
      expect(text(result), contains('too old'));
    });
  });

  group('caps', () {
    test('the event cap stops loading and says so', () async {
      final timeline = _Timeline(
        [for (var i = 0; i < 10; i++) event('\$$i', 'm$i', minutes: i)],
        more: [
          [event(r'$x', 'never loaded')],
        ],
      );
      final result = await runner(timeline, maxEvents: 3).run(html);
      expect(result.truncated, isTrue);
      expect(result.eventCount, 3);
      expect(timeline.loads, 0);
      expect(text(result), contains('stopped at the limit'));
    });

    test('a timeline that stops growing does not loop', () async {
      final timeline = _Timeline([event(r'$1', 'one')])..stuck = true;
      final result = await runner(timeline).run(html);
      expect(result.eventCount, 1);
    });

    test('the time limit ends loading', () async {
      var clock = base;
      final timeline = _Timeline(
        [event(r'$1', 'one')],
        more: [
          [event(r'$2', 'two', minutes: 1)],
          [event(r'$3', 'three', minutes: 2)],
        ],
      );
      timeline.onLoad = () => clock = clock.add(const Duration(minutes: 20));
      final result = await runner(
        timeline,
        maxDuration: const Duration(minutes: 15),
        now: () => clock,
      ).run(html);
      expect(result.truncated, isTrue);
      expect(timeline.loads, 1);
    });

    test('cancelling stops the export and produces nothing', () async {
      final cancel = ExportCancel();
      final timeline = _Timeline(
        [event(r'$1', 'one')],
        more: [
          [event(r'$2', 'two')],
          [event(r'$3', 'three')],
        ],
      );
      timeline.onLoad = () => cancel.isCancelled = true;
      await expectLater(
        runner(timeline).run(html, cancel: cancel),
        throwsA(isA<ExportCancelled>()),
      );
      expect(timeline.loads, 1);
    });

    test('cancelled before the start does nothing', () async {
      final cancel = ExportCancel()..isCancelled = true;
      final timeline = _Timeline([event(r'$1', 'one')], more: [[]]);
      await expectLater(
        runner(timeline).run(html, cancel: cancel),
        throwsA(isA<ExportCancelled>()),
      );
      expect(timeline.loads, 0);
    });

    test('too much text is refused', () async {
      final big = 'x' * ExportLimits.maxTextPerMessage;
      final timeline = _Timeline([
        for (var i = 0; i < 1100; i++) event('\$$i', big, minutes: i),
      ]);
      await expectLater(
        runner(timeline).run(jsonOptions),
        throwsA(isA<ExportTooLarge>()),
      );
    });

    test('the timeline is released however the export ends', () async {
      final ok = _Timeline([event(r'$1', 'one')]);
      await runner(ok).run(html);
      expect(ok.disposed, 1);
      final cancel = ExportCancel()..isCancelled = true;
      final stopped = _Timeline([event(r'$1', 'one')]);
      await expectLater(
        runner(stopped).run(html, cancel: cancel),
        throwsA(isA<ExportCancelled>()),
      );
      expect(stopped.disposed, 1);
    });

    test('progress is reported per page', () async {
      final seen = <int>[];
      final timeline = _Timeline(
        [event(r'$1', 'one')],
        more: [
          [event(r'$2', 'two')],
        ],
      );
      await runner(timeline).run(html, onProgress: seen.add);
      expect(seen, [2]);
    });
  });

  group('media', () {
    Event image(String id, String name, int claimed, {int minutes = 0}) =>
        event(
          id,
          name,
          minutes: minutes,
          content: {
            'msgtype': 'm.image',
            'body': name,
            'filename': name,
            'info': {'size': claimed},
            'file': {
              'url': 'mxc://example.org/$id',
              'key': {'k': 'SECRETKEYVALUE'},
              'iv': 'IV',
              'hashes': {'sha256': 'H'},
            },
          },
        );

    const withMedia = ExportOptions(
      format: ExportFormat.html,
      media: {ExportMediaKind.photosVideos},
    );

    test('media is off by default and nothing is downloaded', () async {
      var calls = 0;
      final result = await runner(
        _Timeline([image(r'$1', 'a.png', 10)]),
        download: (_) async {
          calls++;
          return Uint8List(10);
        },
      ).run(html);
      expect(calls, 0);
      expect(result.fileName, endsWith('.html'));
      expect(text(result), isNot(contains('<a href')));
    });

    test('with media on the result is a zip with generated names', () async {
      final result = await runner(
        _Timeline([image(r'$1', '../../etc/passwd.png', 4)]),
        download: (_) async => Uint8List.fromList([1, 2, 3, 4]),
      ).run(withMedia);
      expect(result.fileName, endsWith('.zip'));
      expect(result.mimeType, 'application/zip');
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final names = archive.files.map((f) => f.name).toList()..sort();
      expect(names.length, 2);
      expect(names, contains('chat.html'));
      final media = names.firstWhere((n) => n.startsWith('media/'));
      expect(media, startsWith('media/000001-'));
      expect(media.substring('media/'.length), isNot(contains('/')));
      expect(media, isNot(contains('..')));
      final chat = archive.files.firstWhere((f) => f.name == 'chat.html');
      expect(utf8.decode(chat.content as List<int>), contains('href="$media"'));
    });

    test('a file claimed above the cap is not downloaded', () async {
      var calls = 0;
      final result = await runner(
        _Timeline([image(r'$1', 'big.png', ExportLimits.maxMediaPerFile + 1)]),
        download: (_) async {
          calls++;
          return Uint8List(1);
        },
      ).run(withMedia);
      expect(calls, 0);
      expect(result.skippedMedia, 1);
      expect(result.fileName, endsWith('.html'));
      expect(text(result), contains('some media skipped'));
    });

    test(
      'a lying small size does not get past the cap on real bytes',
      () async {
        final result = await runner(
          _Timeline([image(r'$1', 'liar.png', 5)]),
          download: (_) async => Uint8List(ExportLimits.maxMediaPerFile + 1),
        ).run(withMedia);
        expect(result.skippedMedia, 1);
        expect(result.fileName, endsWith('.html'));
      },
    );

    test('a failing download is counted, not fatal', () async {
      final result = await runner(
        _Timeline([
          image(r'$1', 'a.png', 3, minutes: 1),
          image(r'$2', 'b.png', 3, minutes: 2),
        ]),
        download: (e) async {
          if (e.eventId == r'$1') throw Exception('gone');
          return Uint8List(3);
        },
      ).run(withMedia);
      expect(result.skippedMedia, 1);
      final archive = ZipDecoder().decodeBytes(result.bytes);
      expect(
        archive.files.where((f) => f.name.startsWith('media/')),
        hasLength(1),
      );
    });

    test('the total cap ends the allowance', () async {
      const count = ExportLimits.maxMediaTotal ~/ ExportLimits.maxMediaPerFile;
      final events = [
        for (var i = 0; i < count + 2; i++)
          image('\$$i', 'f$i.png', 100, minutes: i),
      ];
      var downloaded = 0;
      final result = await runner(
        _Timeline(events),
        download: (_) async {
          downloaded++;
          return Uint8List(ExportLimits.maxMediaPerFile);
        },
      ).run(withMedia);
      expect(result.skippedMedia, 2);
      expect(downloaded, count, reason: 'full allowance: no further downloads');
    });

    group('size and time guards of the media phase', () {
      Event unsized(String id, {int minutes = 0, Object? size}) => event(
        id,
        'x.png',
        minutes: minutes,
        content: {
          'msgtype': 'm.image',
          'body': 'x.png',
          'info': {'size': ?size},
        },
      );

      test('a missing size counts as too large: no download', () async {
        var calls = 0;
        final result = await runner(
          _Timeline([unsized(r'$1'), unsized(r'$2', minutes: 1)]),
          download: (_) async {
            calls++;
            return Uint8List(1);
          },
        ).run(withMedia);
        expect(calls, 0);
        expect(result.skippedMedia, 2);
      });

      test('a size that is not an integer counts as too large', () async {
        var calls = 0;
        final result = await runner(
          _Timeline([
            unsized(r'$1', size: '12'),
            unsized(r'$2', minutes: 1, size: 12.5),
            unsized(r'$3', minutes: 2, size: -4),
          ]),
          download: (_) async {
            calls++;
            return Uint8List(1);
          },
        ).run(withMedia);
        expect(calls, 0);
        expect(result.skippedMedia, 3);
      });

      test('the time limit also ends the media phase', () async {
        var clock = base;
        var calls = 0;
        final result = await runner(
          _Timeline([
            for (var i = 0; i < 5; i++) image('\$$i', 'f$i.png', 3, minutes: i),
          ]),
          maxDuration: const Duration(minutes: 15),
          now: () => clock,
          download: (_) async {
            calls++;
            clock = clock.add(const Duration(minutes: 10));
            return Uint8List(3);
          },
        ).run(withMedia);
        expect(calls, 2, reason: 'the third file starts after 20 minutes');
        expect(result.skippedMedia, 3);
        expect(
          ZipDecoder()
              .decodeBytes(result.bytes)
              .files
              .where((f) => f.name.startsWith('media/')),
          hasLength(2),
        );
      });

      test('cancelling during a download stops the media phase', () async {
        final cancel = ExportCancel();
        var calls = 0;
        await expectLater(
          runner(
            _Timeline([
              for (var i = 0; i < 4; i++)
                image('\$$i', 'f$i.png', 3, minutes: i),
            ]),
            download: (_) async {
              calls++;
              cancel.isCancelled = true;
              return Uint8List(3);
            },
          ).run(withMedia, cancel: cancel),
          throwsA(isA<ExportCancelled>()),
        );
        expect(calls, 1);
      });

      test('cancelling during the last download is not missed', () async {
        final cancel = ExportCancel();
        await expectLater(
          runner(
            _Timeline([image(r'$1', 'only.png', 3)]),
            download: (_) async {
              cancel.isCancelled = true;
              return Uint8List(3);
            },
          ).run(withMedia, cancel: cancel),
          throwsA(isA<ExportCancelled>()),
        );
      });

      test('downloads that turn out too big stop after a few', () async {
        var calls = 0;
        final result = await runner(
          _Timeline([
            for (var i = 0; i < 40; i++)
              image('\$$i', 'f$i.png', 5, minutes: i),
          ]),
          download: (_) async {
            calls++;
            return Uint8List(ExportLimits.maxMediaPerFile + 1);
          },
        ).run(withMedia);
        expect(calls, ExportLimits.maxRejectedDownloads);
        expect(result.skippedMedia, 40);
      });

      test('failed downloads do not use up the rejection allowance', () async {
        var calls = 0;
        final result = await runner(
          _Timeline([
            for (var i = 0; i < 12; i++)
              image('\$$i', 'f$i.png', 5, minutes: i),
          ]),
          download: (_) async {
            calls++;
            return null;
          },
        ).run(withMedia);
        expect(calls, 12);
        expect(result.skippedMedia, 12);
      });
    });

    test('ids sharing a 256 character prefix keep their own files', () async {
      final prefix = '\$${'a' * 255}';
      final first = image('${prefix}1', 'one.png', 3, minutes: 1);
      final second = image('${prefix}2', 'two.png', 3, minutes: 2);
      final downloaded = <String>[];
      final result = await runner(
        _Timeline([first, second]),
        download: (e) async {
          downloaded.add(e.eventId);
          return Uint8List.fromList(
            e.eventId.endsWith('1') ? [1, 1, 1] : [2, 2, 2],
          );
        },
      ).run(withMedia);
      expect(downloaded, ['${prefix}1', '${prefix}2']);
      final byName = {
        for (final f in ZipDecoder().decodeBytes(result.bytes).files)
          f.name: f.content as List<int>,
      };
      final chat = utf8.decode(byName['chat.html']!);
      final one = byName.keys.firstWhere((n) => n.endsWith('one.png'));
      final two = byName.keys.firstWhere((n) => n.endsWith('two.png'));
      expect(byName[one], [1, 1, 1]);
      expect(byName[two], [2, 2, 2]);
      expect(chat, contains('href="$one"'));
      expect(chat, contains('href="$two"'));
    });

    test('other kinds stay out when only photos are chosen', () async {
      var calls = 0;
      final file = event(
        r'$f',
        'doc.pdf',
        content: {'msgtype': 'm.file', 'body': 'doc.pdf'},
      );
      await runner(
        _Timeline([file]),
        download: (_) async {
          calls++;
          return Uint8List(1);
        },
      ).run(withMedia);
      expect(calls, 0);
    });

    test('the json export never carries the attachment secrets', () async {
      final result = await runner(
        _Timeline([image(r'$1', 'a.png', 10)]),
      ).run(jsonOptions);
      expect(text(result), isNot(contains('SECRETKEYVALUE')));
    });
  });

  group('file name', () {
    test('a hostile room name cannot shape the file name', () async {
      final result = await runner(
        _Timeline([event(r'$1', 'x')]),
        name: '../../etc/<script>alert(1)</script>"; rm -rf',
      ).run(html);
      expect(
        result.fileName,
        matches(RegExp(r'^export-[A-Za-z0-9_-]+-\d{8}\.html$')),
      );
      expect(result.fileName.length, lessThan(70));
    });

    test('an empty name falls back', () async {
      final result = await runner(
        _Timeline([event(r'$1', 'x')]),
        name: '   ',
      ).run(jsonOptions);
      expect(result.fileName, startsWith('export-chat-'));
      expect(result.fileName, endsWith('.json'));
    });
  });
}
