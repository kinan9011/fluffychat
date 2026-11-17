// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  const rootId = r'$root:example.org';
  const childId = r'$child:example.org';

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(harness.tearDown);

  Event threadChild() => Event(
    type: EventTypes.Message,
    content: {
      'msgtype': 'm.text',
      'body': 'reply in the topic',
      'm.relates_to': {'rel_type': 'm.thread', 'event_id': rootId},
    },
    room: harness.room,
    eventId: childId,
    senderId: '@bob:example.org',
    originServerTs: DateTime.now(),
  );

  Future<ChatController> openThread(
    WidgetTester tester, {
    int reads = 1,
  }) async {
    await harness.open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = tester.state<ChatController>(
      find.byType(ChatPageWithRoom),
    );
    controller.timeline!.events.insert(0, threadChild());
    controller.enterThread(rootId);
    await harness.settle(tester, rounds: 3);
    api.clear();
    for (var i = 0; i < reads; i++) {
      controller.setReadMarker();
    }
    await harness.settle(tester, rounds: 3);
    return controller;
  }

  testWidgets('reading in a topic sends a private threaded receipt only', (
    tester,
  ) async {
    await openThread(tester);
    expect(api.requests('/read_markers'), isEmpty);
    expect(api.requests('/receipt/m.read/'), isEmpty);
    final private = api.requests('/receipt/m.read.private/');
    expect(private, hasLength(1));
    expect(private.single.path, contains(childId));
    expect((private.single.json! as Map)['thread_id'], rootId);
    await harness.finish(tester);
  });

  testWidgets('with public receipts on the public one is threaded too', (
    tester,
  ) async {
    await AppSettings.sendPublicReadReceipts.setItem(true);
    await openThread(tester);
    expect(api.requests('/read_markers'), isEmpty);
    final public = api.requests('/receipt/m.read/');
    expect(public, hasLength(1));
    expect((public.single.json! as Map)['thread_id'], rootId);
    expect(api.requests('/receipt/m.read.private/'), hasLength(1));
    await harness.finish(tester);
  });

  testWidgets('a topic read never moves the main read marker', (tester) async {
    await AppSettings.sendPublicReadReceipts.setItem(true);
    await openThread(tester);
    expect(api.log.where((r) => r.body.contains('m.fully_read')), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the same event is not sent twice', (tester) async {
    await openThread(tester, reads: 3);
    expect(api.requests('/receipt/m.read.private/'), hasLength(1));
    await harness.finish(tester);
  });
}
