// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/topics/topic.dart';
import 'package:odango/utils/topics/topic_loader.dart';
import 'package:odango/utils/topics/topics_model.dart';

import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  var now = DateTime.utc(2026, 11, 17, 12);

  setUpAll(() async {
    client = await prepareTestClient();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  setUp(() => now = DateTime.utc(2026, 11, 17, 12));

  MatrixEvent root(
    String id, {
    int minutes = 0,
    String body = 'topic',
    String type = EventTypes.Message,
    Map<String, Object?>? unsigned,
    Map<String, Object?>? content,
  }) => MatrixEvent(
    type: type,
    content: content ?? {'msgtype': 'm.text', 'body': body},
    senderId: '@bob:example.org',
    eventId: id,
    originServerTs: DateTime.utc(2026, 11, 1).add(Duration(minutes: minutes)),
    unsigned: unsigned,
  );

  Map<String, Object?> bundle(int count, int tsMinutes) => {
    'm.relations': {
      'm.thread': {
        'count': count,
        'latest_event': {
          'sender': '@bob:example.org',
          'origin_server_ts': DateTime.utc(
            2026,
            11,
            1,
          ).add(Duration(minutes: tsMinutes)).millisecondsSinceEpoch,
          'content': {'body': 'last'},
        },
      },
    },
  };

  TopicLoader loader(
    List<GetThreadRootsResponse> pages, {
    List<String?>? froms,
    EventDecrypt? decrypt,
    Duration minInterval = const Duration(seconds: 5),
  }) {
    var call = 0;
    return TopicLoader(
      room,
      fetch: (roomId, {from}) async {
        froms?.add(from);
        return pages[call++ % pages.length];
      },
      decrypt: decrypt,
      now: () => now,
      minInterval: minInterval,
    );
  }

  test('topics are sorted by their latest activity', () async {
    final topics = await loader([
      GetThreadRootsResponse(
        chunk: [
          root(r'$a:x', body: 'Old', unsigned: bundle(2, 10)),
          root(r'$b:x', body: 'New', unsigned: bundle(5, 90)),
          root(r'$c:x', body: 'Mid', unsigned: bundle(1, 50)),
        ],
      ),
    ]).load();
    expect(topics.map((t) => t.title), ['New', 'Mid', 'Old']);
    expect(topics.first.replyCount, 5);
  });

  test('pages are followed, at most four', () async {
    final froms = <String?>[];
    final pages = [
      for (var p = 0; p < 10; p++)
        GetThreadRootsResponse(
          chunk: [root('\$p$p:x', minutes: p)],
          nextBatch: 'page${p + 1}',
        ),
    ];
    final topics = await loader(pages, froms: froms).load();
    expect(froms, [null, 'page1', 'page2', 'page3']);
    expect(topics, hasLength(4));
  });

  test('a page stops at its last token', () async {
    final froms = <String?>[];
    await loader([
      GetThreadRootsResponse(chunk: [root(r'$a:x')], nextBatch: 'next'),
      GetThreadRootsResponse(chunk: [root(r'$b:x')]),
    ], froms: froms).load();
    expect(froms, [null, 'next']);
  });

  test('only the first 100 entries of a page are used', () async {
    final topics = await loader([
      GetThreadRootsResponse(
        chunk: [for (var i = 0; i < 1000; i++) root('\$e$i:x', minutes: i)],
      ),
    ]).load();
    expect(topics, hasLength(TopicParser.maxRootsPerPage));
  });

  test('never more than 200 topics', () async {
    final pages = [
      for (var p = 0; p < 4; p++)
        GetThreadRootsResponse(
          chunk: [
            for (var i = 0; i < 100; i++)
              root('\$p${p}e$i:x', minutes: p * 100 + i),
          ],
          nextBatch: 'n$p',
        ),
    ];
    final topics = await loader(pages).load();
    expect(topics, hasLength(TopicParser.maxTopics));
  });

  test('entries without a usable id are skipped, duplicates merged', () async {
    final topics = await loader([
      GetThreadRootsResponse(
        chunk: [
          root('not-an-id'),
          root(r'$ok:x', body: 'one'),
          root(r'$ok:x', body: 'duplicate'),
          root('\$${'a' * 400}'),
        ],
      ),
    ]).load();
    expect(topics.map((t) => t.title), ['one']);
  });

  test('an encrypted root is decrypted for its title only', () async {
    final encrypted = root(
      r'$enc:x',
      type: EventTypes.Encrypted,
      content: {'algorithm': 'm.megolm.v1.aes-sha2', 'ciphertext': 'xx'},
    );
    final topics = await loader(
      [
        GetThreadRootsResponse(chunk: [encrypted]),
      ],
      decrypt: (event) async => Event(
        type: EventTypes.Message,
        content: {
          'msgtype': 'm.text',
          'body': 'Secret plans',
          topicContentKey: {'icon': 'lightbulb'},
        },
        room: room,
        eventId: event.eventId,
        senderId: event.senderId,
        originServerTs: event.originServerTs,
      ),
    ).load();
    expect(topics.single.title, 'Secret plans');
    expect(topics.single.icon, 'lightbulb');
  });

  test('an undecryptable root is an untitled topic, not a failure', () async {
    final topics = await loader([
      GetThreadRootsResponse(
        chunk: [
          root(
            r'$enc:x',
            type: EventTypes.Encrypted,
            content: {'algorithm': 'x', 'ciphertext': 'y'},
          ),
        ],
      ),
    ], decrypt: (_) async => throw Exception('no keys')).load();
    expect(topics.single.title, isEmpty);
    expect(topics.single.rootEventId, r'$enc:x');
  });

  test('asking again within five seconds does not ask the server', () async {
    final froms = <String?>[];
    final subject = loader([
      GetThreadRootsResponse(chunk: [root(r'$a:x')]),
    ], froms: froms);
    await subject.load();
    now = now.add(const Duration(seconds: 4));
    await subject.load();
    expect(froms, hasLength(1));
    now = now.add(const Duration(seconds: 2));
    await subject.load();
    expect(froms, hasLength(2));
  });

  test('two calls at once share one request', () async {
    final froms = <String?>[];
    final subject = loader([
      GetThreadRootsResponse(chunk: [root(r'$a:x')]),
    ], froms: froms);
    final results = await Future.wait([subject.load(), subject.load()]);
    expect(froms, hasLength(1));
    expect(results.first, results.last);
  });

  group('after a failure', () {
    var calls = 0;
    late TopicLoader subject;

    setUp(() {
      calls = 0;
      subject = TopicLoader(
        room,
        fetch: (roomId, {from}) async {
          if (calls++ < 2) throw Exception('boom');
          return GetThreadRootsResponse(chunk: [root(r'$a:x')]);
        },
        now: () => now,
      );
    });

    test('an error is TopicsLoadFailed', () async {
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
    });

    test('asking again within five seconds does not ask the server, and '
        'still reports the failure', () async {
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      now = now.add(const Duration(seconds: 4));
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      expect(calls, 1);
    });

    test('the wait doubles with every failure up to a minute', () async {
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      now = now.add(const Duration(seconds: 6));
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      expect(calls, 2);
      now = now.add(const Duration(seconds: 6));
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      expect(calls, 2);
      now = now.add(const Duration(seconds: 5));
      expect(await subject.load(), hasLength(1));
      expect(calls, 3);
    });

    test('the wait never exceeds a minute', () async {
      final failing = TopicLoader(
        room,
        fetch: (roomId, {from}) async {
          calls++;
          throw Exception('boom');
        },
        now: () => now,
      );
      for (var i = 0; i < 12; i++) {
        await expectLater(failing.load(), throwsA(isA<TopicsLoadFailed>()));
        now = now.add(const Duration(seconds: 61));
      }
      expect(calls, 12);
    });

    test('an explicit retry is the one call that skips the wait', () async {
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      await expectLater(
        subject.load(force: true),
        throwsA(isA<TopicsLoadFailed>()),
      );
      expect(calls, 2);
    });

    test('a timeline-driven model cannot send more than one request in the '
        'wait', () async {
      final model = TopicsModel(room, loader: subject);
      for (var i = 0; i < 6; i++) {
        await model.load(const []);
      }
      expect(calls, 1);
      expect(model.status.value, TopicsStatus.failed);
      model.dispose();
    });

    test('a success clears the failures', () async {
      await expectLater(subject.load(), throwsA(isA<TopicsLoadFailed>()));
      await expectLater(
        subject.load(force: true),
        throwsA(isA<TopicsLoadFailed>()),
      );
      expect(await subject.load(force: true), hasLength(1));
      now = now.add(const Duration(seconds: 6));
      expect(await subject.load(), hasLength(1));
      expect(calls, 4);
    });
  });

  group('mergeTimelineRoots', () {
    Event timelineRoot(
      String id, {
      bool topic = true,
      int minutes = 0,
    }) => Event(
      type: EventTypes.Message,
      content: {
        'msgtype': 'm.text',
        'body': 'Fresh topic',
        if (topic) topicContentKey: {'title': 'Fresh topic', 'icon': 'forum'},
      },
      room: room,
      eventId: id,
      senderId: '@bob:example.org',
      originServerTs: DateTime.utc(2026, 11, 2).add(Duration(minutes: minutes)),
    );

    test('a topic without replies appears once', () {
      final merged = TopicLoader.mergeTimelineRoots(const [], [
        timelineRoot(r'$new:x'),
        timelineRoot(r'$new:x'),
        timelineRoot(r'$plain:x', topic: false),
      ]);
      expect(merged.map((t) => t.rootEventId), [r'$new:x']);
      expect(merged.single.icon, 'forum');
    });

    test('a topic the server listed is not replaced', () async {
      final listed = await loader([
        GetThreadRootsResponse(
          chunk: [
            root(r'$new:x', body: 'Server title', unsigned: bundle(3, 5)),
          ],
        ),
      ]).load();
      final merged = TopicLoader.mergeTimelineRoots(listed, [
        timelineRoot(r'$new:x'),
      ]);
      expect(merged.single.title, 'Server title');
      expect(merged.single.replyCount, 3);
    });

    test('the newest activity comes first and the total is capped', () {
      final merged = TopicLoader.mergeTimelineRoots(const [], [
        for (var i = 0; i < 250; i++) timelineRoot('\$t$i:x', minutes: i),
      ]);
      expect(merged, hasLength(TopicParser.maxTopics));
      expect(
        merged.first.lastActivity.isAfter(merged.last.lastActivity),
        isTrue,
      );
    });
  });

  test('topics are never stored: no preferences, cache or logs of titles', () {
    for (final file in Directory('lib/utils/topics').listSync()) {
      if (file is! File) continue;
      final source = file.readAsStringSync();
      for (final forbidden in [
        'SharedPreferences',
        'AppSettings',
        'customCache',
        'storeFile',
        'database',
        'Logs().d(',
        'Logs().v(',
        'Logs().i(',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: file.path);
      }
    }
  });
}
