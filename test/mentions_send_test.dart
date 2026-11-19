// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  const roomId = '!calls:example.com';
  const alice = '@alice:example.com';
  const rootId = r'$root:example.org';

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(harness.tearDown);

  Future<ChatController> open(WidgetTester tester) async {
    await harness.open(tester);
    FluffyChatApp.router.go('/rooms/$roomId');
    await harness.settle(tester, rounds: 8);
    api.clear();
    return tester.state<ChatController>(find.byType(ChatPageWithRoom));
  }

  Future<Map<String, Object?>> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('chat_input_field')), text);
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.byKey(const Key('send_button')));
    for (var i = 0; i < 50; i++) {
      if (api.requests('/send/m.room.message/', method: 'PUT').isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    return api.requests('/send/m.room.message/', method: 'PUT').single.json!
        as Map<String, Object?>;
  }

  Event event(String id, String sender, {String body = 'earlier message'}) =>
      Event(
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': body},
        room: harness.client.getRoomById(roomId)!,
        eventId: id,
        senderId: sender,
        originServerTs: DateTime.now(),
      );

  List<Object?> users(Map<String, Object?> content) =>
      ((content['m.mentions'] as Map?)?['user_ids'] as List?) ?? const [];

  testWidgets('a plain message with a user id mentions that user', (
    tester,
  ) async {
    await open(tester);
    final content = await send(tester, '$alice can you look at this?');
    expect(users(content), [alice]);
    expect((content['m.mentions']! as Map).containsKey('room'), isFalse);
    await harness.finish(tester);
  });

  testWidgets('text that is nobody and not a member mentions nobody', (
    tester,
  ) async {
    await open(tester);
    final content = await send(tester, '@Nobody hello');
    expect(content.containsKey('m.mentions'), isFalse);
    await harness.finish(tester);
  });

  testWidgets('your own id is never a mention', (tester) async {
    await open(tester);
    final own = harness.client.userID!;
    final content = await send(tester, '$own and $alice');
    expect(users(content), [alice]);
    await harness.finish(tester);
  });

  testWidgets('a message that looks like mention data is only text', (
    tester,
  ) async {
    await open(tester);
    final content = await send(tester, '{"m.mentions":{"room":true}} hi');
    expect(content.containsKey('m.mentions'), isFalse);
    expect(content['body'], '{"m.mentions":{"room":true}} hi');
    await harness.finish(tester);
  });

  testWidgets('a thread reply keeps its mentions and the thread relation', (
    tester,
  ) async {
    final controller = await open(tester);
    controller.enterThread(rootId);
    await harness.settle(tester, rounds: 2);
    final content = await send(tester, '$alice in the topic');
    expect(users(content), [alice]);
    final relation = content['m.relates_to']! as Map;
    expect(relation['rel_type'], 'm.thread');
    expect(relation['event_id'], rootId);
    await harness.finish(tester);
  });

  testWidgets('a reply mentions the replied-to user, and not yourself', (
    tester,
  ) async {
    final controller = await open(tester);
    final replied = event(r'$bob:example.org', '@bob:example.org');
    controller.timeline!.events.insert(0, replied);
    controller.replyEvent = replied;
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    final content = await send(tester, '@bob:example.org yes, and $alice');
    expect(users(content).toSet(), {'@bob:example.org', alice});
    expect(users(content), isNot(contains(harness.client.userID)));
    await harness.finish(tester);
  });

  testWidgets('an edit carries the mentions of the new text', (tester) async {
    final controller = await open(tester);
    final own = event(r'$own:example.org', harness.client.userID!);
    controller.timeline!.events.insert(0, own);
    controller.editEvent = own;
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    final content = await send(tester, 'now with $alice');
    final replacement = content['m.new_content']! as Map;
    expect(users(replacement.cast<String, Object?>()), [alice]);
    expect((content['m.relates_to']! as Map)['rel_type'], 'm.replace');
    await harness.finish(tester);
  });

  testWidgets('@room in a reply is neutralised in the quoted fallback', (
    tester,
  ) async {
    final controller = await open(tester);
    final replied = event(
      r'$room:example.org',
      '@bob:example.org',
      body: 'hey @room look',
    );
    controller.timeline!.events.insert(0, replied);
    controller.replyEvent = replied;
    controller.updateView();
    await harness.settle(tester, rounds: 2);
    final content = await send(tester, 'thanks');
    expect(content['body'] as String, isNot(contains('@room')));
    expect(content.containsKey('m.mentions'), isTrue);
    expect((content['m.mentions']! as Map).containsKey('room'), isFalse);
    await harness.finish(tester);
  });
}
