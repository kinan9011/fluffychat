// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  const roomId = '!calls:example.com';

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    await AppSettings.sendTypingNotifications.setItem(false);
    api.threadsResponse = null;
    api.getOverrides.clear();
    api.clear();
  });
  tearDown(harness.tearDown);

  Map<String, Object?> root(
    String id,
    String title, {
    int count = 3,
    int minutesAgo = 5,
    String icon = 'tag',
  }) => {
    'type': 'm.room.message',
    'event_id': id,
    'sender': '@bob:example.org',
    'origin_server_ts': DateTime.now()
        .subtract(Duration(minutes: minutesAgo))
        .millisecondsSinceEpoch,
    'content': {
      'msgtype': 'm.text',
      'body': title,
      'com.swovo.odango.topic': {'title': title, 'icon': icon},
    },
    'unsigned': {
      'm.relations': {
        'm.thread': {
          'count': count,
          'latest_event': {
            'sender': '@bob:example.org',
            'origin_server_ts': DateTime.now()
                .subtract(Duration(minutes: minutesAgo))
                .millisecondsSinceEpoch,
            'content': {'body': 'last in $title'},
          },
        },
      },
    },
  };

  Future<void> openTopics(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
    Brightness brightness = Brightness.light,
  }) async {
    await harness.open(
      tester,
      width: width,
      height: height,
      brightness: brightness,
    );
    FluffyChatApp.router.go('/rooms/$roomId/topics');
    await harness.settle(tester, rounds: 8);
  }

  testWidgets('General first, then topics by activity, with counts', (
    tester,
  ) async {
    api.threadsResponse = {
      'chunk': [
        root(r'$a:example.org', 'Old topic', minutesAgo: 600),
        root(
          r'$b:example.org',
          'Releases',
          minutesAgo: 2,
          icon: 'rocket_launch',
        ),
      ],
    };
    await openTopics(tester);
    expect(find.byKey(const ValueKey('topic_general')), findsOneWidget);
    expect(find.text('Releases'), findsOneWidget);
    expect(find.text('Old topic'), findsOneWidget);
    final general = tester.getTopLeft(
      find.byKey(const ValueKey('topic_general')),
    );
    final releases = tester.getTopLeft(
      find.byKey(const ValueKey(r'topic_$b:example.org')),
    );
    final old = tester.getTopLeft(
      find.byKey(const ValueKey(r'topic_$a:example.org')),
    );
    expect(general.dy, lessThan(releases.dy));
    expect(releases.dy, lessThan(old.dy));
    expect(find.textContaining('2 topics'), findsOneWidget);
    expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
    expect(find.textContaining('last in Releases'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a topic opens as a thread with the target line', (tester) async {
    api.threadsResponse = {
      'chunk': [root(r'$b:example.org', 'Releases')],
    };
    api.getOverrides['/event/%24b%3Aexample.org'] = {
      ...root(r'$b:example.org', 'Releases'),
      'room_id': roomId,
    };
    await openTopics(tester);
    await tester.tap(find.byKey(const ValueKey(r'topic_$b:example.org')));
    await harness.settle(tester, rounds: 8);
    expect(
      FluffyChatApp.router.state.uri.queryParameters['thread'],
      r'$b:example.org',
    );
    final controller = tester.state<ChatController>(
      find.byType(ChatPageWithRoom),
    );
    expect(controller.activeThreadId, r'$b:example.org');
    expect(find.byKey(const ValueKey('sending_to_topic')), findsOneWidget);
    expect(find.text('Sending to # Releases'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('"As one chat" goes to the room', (tester) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await openTopics(tester);
    await tester.tap(find.byKey(const ValueKey('topics_as_one_chat')));
    await harness.settle(tester, rounds: 6);
    expect(FluffyChatApp.router.state.uri.path, '/rooms/$roomId');
    expect(FluffyChatApp.router.state.uri.queryParameters, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('an empty room says so and offers a new topic', (tester) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await openTopics(tester);
    expect(find.textContaining('No topics yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('topics_new')), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a failed load shows a retry', (tester) async {
    api.threadsResponse = {'chunk': 'not a list'};
    await openTopics(tester);
    expect(find.textContaining("Couldn't load topics"), findsOneWidget);
    expect(find.byKey(const ValueKey('topics_retry')), findsOneWidget);
    api.threadsResponse = {
      'chunk': [root(r'$b:example.org', 'Back again')],
    };
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.byKey(const ValueKey('topics_retry')));
    await harness.settle(tester, rounds: 8);
    expect(find.text('Back again'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a server without threaded receipts shows no topics', (
    tester,
  ) async {
    api.getOverrides['/versions'] = {
      'versions': ['v1.1'],
      'unstable_features': <String, bool>{},
    };
    await openTopics(tester);
    expect(find.text("Your server doesn't support topics."), findsOneWidget);
    expect(api.requests('/threads'), isEmpty);
    expect(find.byKey(const ValueKey('topics_new')), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('New topic sends one root with a clean title and an icon', (
    tester,
  ) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await openTopics(tester);
    await tester.tap(find.byKey(const ValueKey('topics_new')));
    await harness.settle(tester, rounds: 4);
    final create = find.byKey(const ValueKey('topic_create'));
    expect(tester.widget<InkWell>(create).onTap, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('topic_title_field')),
      '  Rel${String.fromCharCode(0x200b)}eases  ',
    );
    await tester.tap(find.byKey(const ValueKey('topic_icon_rocket_launch')));
    await tester.pump();
    api.clear();
    await tester.tap(create);
    for (
      var i = 0;
      i < 50 && api.requests('/send/', method: 'PUT').isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final sent = api.requests('/send/m.room.message/', method: 'PUT');
    expect(sent, hasLength(1));
    final body = sent.single.json! as Map;
    expect(body['body'], 'Rel eases');
    expect(body['com.swovo.odango.topic'], {
      'title': 'Rel eases',
      'icon': 'rocket_launch',
    });
    await harness.finish(tester);
  });

  Future<void> waitForPuts(WidgetTester tester, int count) async {
    for (
      var i = 0;
      i < 50 && api.requests('/send/', method: 'PUT').length < count;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await harness.settle(tester, rounds: 3);
  }

  testWidgets('a retry after a failed send reuses the transaction id, an '
      'edited one gets a new id', (tester) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await openTopics(tester);
    await tester.tap(find.byKey(const ValueKey('topics_new')));
    await harness.settle(tester, rounds: 4);
    final create = find.byKey(const ValueKey('topic_create'));
    final field = find.byKey(const ValueKey('topic_title_field'));
    String txid(RecordedRequest r) => r.path.split('/').last;
    await tester.enterText(field, 'Releases');
    await tester.pump();
    api.clear();
    api.failNextSend = true;
    await tester.tap(create);
    await waitForPuts(tester, 1);
    api.failNextSend = true;
    await tester.tap(create);
    await waitForPuts(tester, 2);
    final same = api.requests('/send/', method: 'PUT');
    expect(txid(same[0]), txid(same[1]));
    await tester.enterText(field, 'Releases 2');
    await tester.pump();
    await tester.tap(create);
    await waitForPuts(tester, 3);
    final all = api.requests('/send/', method: 'PUT');
    expect(all, hasLength(3));
    expect(txid(all[2]), isNot(txid(all[1])));
    await harness.finish(tester);
  });

  testWidgets('the New topic sheet on a small screen with the keyboard open '
      'keeps Create topic reachable', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 150);
    addTearDown(tester.view.resetViewInsets);
    api.threadsResponse = {'chunk': <Object>[]};
    await openTopics(tester, width: 320, height: 480);
    await tester.tap(find.byKey(const ValueKey('topics_new')));
    await harness.settle(tester, rounds: 4);
    await tester.enterText(
      find.byKey(const ValueKey('topic_title_field')),
      'Releases',
    );
    await tester.pump();
    final create = find.byKey(const ValueKey('topic_create'));
    final rect = tester.getRect(create);
    expect(rect.bottom, lessThanOrEqualTo(480 - 150 + 1));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(tester.widget<InkWell>(create).onTap, isNotNull);
    expect(tester.takeException(), isNull);
    api.clear();
    await tester.tap(create);
    await waitForPuts(tester, 1);
    expect(api.requests('/send/', method: 'PUT'), hasLength(1));
    await harness.finish(tester);
  });

  testWidgets('a small screen with a large text size does not overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    api.threadsResponse = {
      'chunk': [
        root(r'$b:example.org', 'A rather long topic name that wraps ' * 3),
        root(r'$c:example.org', 'Short', minutesAgo: 30),
      ],
    };
    await openTopics(tester, width: 320, height: 480);
    expect(tester.takeException(), isNull);
    final short = find.byKey(const ValueKey(r'topic_$c:example.org'));
    await tester.dragUntilVisible(
      short,
      find.byType(ListView).first,
      const Offset(0, -150),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(short).height, greaterThanOrEqualTo(72));
    await harness.finish(tester);
  });

  testWidgets('a thread in the address that is not an event id is ignored', (
    tester,
  ) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await harness.open(tester);
    for (final bad in [
      'garbage',
      r'$',
      r'$a b',
      r'$<script>:example.org',
      '!room:example.org',
      '',
    ]) {
      FluffyChatApp.router.go(
        '/rooms/$roomId?thread=${Uri.encodeQueryComponent(bad)}',
      );
      await harness.settle(tester, rounds: 5);
      final controller = tester.state<ChatController>(
        find.byType(ChatPageWithRoom),
      );
      expect(controller.activeThreadId, isNull, reason: bad);
    }
    await harness.finish(tester);
  });

  testWidgets('a thread that is not in the room is ignored, one that is '
      'opens', (tester) async {
    api.threadsResponse = {'chunk': <Object>[]};
    api.getOverrides['/event/%24ok%3Aexample.org'] = {
      'type': 'm.room.message',
      'event_id': r'$ok:example.org',
      'sender': '@bob:example.org',
      'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
      'room_id': roomId,
      'content': {'msgtype': 'm.text', 'body': 'root'},
    };
    await harness.open(tester);
    FluffyChatApp.router.go(
      '/rooms/$roomId?thread=${Uri.encodeQueryComponent(r'$nowhere:example.org')}',
    );
    await harness.settle(tester, rounds: 8);
    expect(
      tester
          .state<ChatController>(find.byType(ChatPageWithRoom))
          .activeThreadId,
      isNull,
    );
    FluffyChatApp.router.go(
      '/rooms/$roomId?thread=${Uri.encodeQueryComponent(r'$ok:example.org')}',
    );
    await harness.settle(tester, rounds: 8);
    expect(
      tester
          .state<ChatController>(find.byType(ChatPageWithRoom))
          .activeThreadId,
      r'$ok:example.org',
    );
    await harness.finish(tester);
  });
}
