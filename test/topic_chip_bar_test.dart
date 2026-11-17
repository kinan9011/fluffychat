// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  const groupId = '!calls:example.com';

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

  Map<String, Object?> root(String id, String title, {int minutesAgo = 5}) => {
    'type': 'm.room.message',
    'event_id': id,
    'sender': '@bob:example.org',
    'origin_server_ts': DateTime.now()
        .subtract(Duration(minutes: minutesAgo))
        .millisecondsSinceEpoch,
    'content': {
      'msgtype': 'm.text',
      'body': title,
      'im.fluffychat.topic': {'title': title, 'icon': 'forum'},
    },
    'unsigned': {
      'm.relations': {
        'm.thread': {'count': 2},
      },
    },
  };

  Future<void> open(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
    bool expectBar = true,
    String roomId = groupId,
  }) async {
    await harness.open(tester, width: width, height: height);
    FluffyChatApp.router.go('/rooms/$roomId');
    await harness.settle(tester, rounds: 6);
    final bar = find.byKey(const ValueKey('topic_chip_general'));
    for (var i = 0; i < (expectBar ? 60 : 15); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (expectBar && bar.evaluate().isNotEmpty) break;
    }
    await harness.settle(tester, rounds: 4);
  }

  Finder chip(String key) => find.byKey(ValueKey(key));

  testWidgets('the chip bar shows General, topics and the Topics chip', (
    tester,
  ) async {
    api.threadsResponse = {
      'chunk': [
        root(r'$a:example.org', 'Releases'),
        root(r'$b:example.org', 'Design', minutesAgo: 50),
      ],
    };
    await open(tester);
    expect(chip('topic_chip_general'), findsOneWidget);
    expect(chip(r'topic_chip_$a:example.org'), findsOneWidget);
    expect(chip(r'topic_chip_$b:example.org'), findsOneWidget);
    expect(chip('topic_chip_all'), findsOneWidget);
    final inkWell = find.descendant(
      of: chip('topic_chip_general'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(inkWell).height, greaterThanOrEqualTo(44));
    await harness.finish(tester);
  });

  testWidgets('no topics, no chip bar', (tester) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await open(tester, expectBar: false);
    expect(chip('topic_chip_general'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('without threaded receipts on the server there is no chip bar '
      'and no request for topics', (tester) async {
    api.getOverrides['/versions'] = {
      'versions': ['v1.1'],
      'unstable_features': <String, bool>{},
    };
    api.threadsResponse = {
      'chunk': [root(r'$a:example.org', 'Releases')],
    };
    await open(tester, expectBar: false);
    expect(chip('topic_chip_general'), findsNothing);
    expect(api.requests('/threads'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a direct chat has no chip bar and no request for topics', (
    tester,
  ) async {
    api.threadsResponse = {
      'chunk': [root(r'$a:example.org', 'Releases')],
    };
    await open(tester, expectBar: false, roomId: harness.room.id);
    expect(harness.room.isDirectChat, isTrue);
    expect(chip('topic_chip_general'), findsNothing);
    expect(api.requests('/threads'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a chip opens the topic, General closes it again', (
    tester,
  ) async {
    api.threadsResponse = {
      'chunk': [root(r'$a:example.org', 'Releases')],
    };
    await open(tester);
    final controller = tester.state<ChatController>(
      find.byType(ChatPageWithRoom),
    );
    await tester.tap(chip(r'topic_chip_$a:example.org'));
    await harness.settle(tester, rounds: 3);
    expect(controller.activeThreadId, r'$a:example.org');
    expect(find.text('Sending to # Releases'), findsOneWidget);
    await tester.tap(chip('topic_chip_general'));
    await harness.settle(tester, rounds: 3);
    expect(controller.activeThreadId, isNull);
    expect(find.byKey(const ValueKey('sending_to_topic')), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('at most eight topics, plus General and Topics', (tester) async {
    api.threadsResponse = {
      'chunk': [
        for (var i = 0; i < 12; i++)
          root('\$t$i:example.org', 'Topic $i', minutesAgo: i + 1),
      ],
    };
    await open(tester, width: 2400);
    final chips = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('topic_chip_'),
    );
    expect(chips, findsNWidgets(8 + 2));
    await harness.finish(tester);
  });

  testWidgets('the Topics chip and the menu entry open the list', (
    tester,
  ) async {
    api.threadsResponse = {
      'chunk': [root(r'$a:example.org', 'Releases')],
    };
    await open(tester);
    await tester.tap(chip('topic_chip_all'));
    await harness.settle(tester, rounds: 4);
    expect(FluffyChatApp.router.state.uri.path, '/rooms/$groupId/topics');
    await harness.finish(tester);
  });

  testWidgets('the overflow menu has Topics for a group', (tester) async {
    api.threadsResponse = {'chunk': <Object>[]};
    await open(tester, expectBar: false);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 2);
    expect(find.text('Topics'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a small screen keeps the composer and the bar visible', (
    tester,
  ) async {
    api.threadsResponse = {
      'chunk': [root(r'$a:example.org', 'Releases')],
    };
    await open(tester, width: 320, height: 480);
    expect(tester.takeException(), isNull);
    expect(chip('topic_chip_general'), findsOneWidget);
    expect(find.byKey(const Key('chat_input_field')), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('the overflow menu has no Topics when the server cannot', (
    tester,
  ) async {
    api.getOverrides['/versions'] = {
      'versions': ['v1.1'],
      'unstable_features': <String, bool>{},
    };
    await open(tester, expectBar: false);
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 2);
    expect(find.text('Disappearing messages'), findsOneWidget);
    expect(find.text('Topics'), findsNothing);
    await harness.finish(tester);
  });
}
