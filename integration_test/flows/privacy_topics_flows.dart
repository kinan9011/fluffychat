// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/events/message_bubble.dart';
import 'package:fluffychat/pages/chat/events/poll.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'shell_navigation.dart';

Future<void> appearOfflineFlow(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._appearOffline());

Future<void> pollFlow(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._poll());

Future<void> topicFlow(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._topic());

Future<void> disappearingFlow(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._disappearing());

Finder _bubbleWith(String text) => find.descendant(
  of: find.byType(MessageBubble),
  matching: find.textContaining(text, findRichText: true),
);

extension on FluffyChatTester {
  Future<void> _untilTrue(
    Future<bool> Function() check, {
    Duration timeout = const Duration(seconds: 60),
    required String reason,
  }) async {
    final end = DateTime.now().add(timeout);
    while (!await check()) {
      if (DateTime.now().isAfter(end)) throw Exception('Timed out: $reason');
      await tester.pump(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _setSwitch(String title, bool wanted) async {
    final tile = find.widgetWithText(SwitchListTile, title);
    await waitFor(tile);
    if (tester.widget<SwitchListTile>(tile).value == wanted) return;
    await tapOn(tile);
    expect(tester.widget<SwitchListTile>(tile).value, wanted, reason: title);
  }

  Future<({SynapseUser alice, SynapseUser bob, String roomId})> _openRoom(
    String name, {
    bool aliceCreates = false,
  }) async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final creator = aliceCreates ? alice : bob;
    final guest = aliceCreates ? bob : alice;
    final roomId = await creator.createRoom(name, invite: [guest.userId]);
    await guest.join(roomId);
    await creator.sendText(roomId, '$name greeting');
    final row = find.widgetWithText(ChatListItem, name);
    await waitFor(row);
    await tapOn(row);
    await waitFor(_bubbleWith('$name greeting'));
    return (alice: alice, bob: bob, roomId: roomId);
  }

  Future<void> _appearOffline() async {
    await ensureLoggedIn();
    final alice = await SynapseUser.login(user1Name, user1Pw);
    await openTab('Settings');
    await tapOn('Security');
    await _setSwitch('Show online status', false);
    await _setSwitch('Appear offline', false);
    await _untilTrue(
      () async => await alice.presence() == 'offline',
      reason: 'by default the homeserver sees the user as offline',
    );

    await _setSwitch('Show online status', true);
    await _setSwitch('Appear offline', true);
    await _untilTrue(
      () async => await alice.presence() == 'offline',
      reason: 'appear offline keeps the user offline',
    );
    await tester.pump(const Duration(seconds: 5));
    expect(await alice.presence(), 'offline');

    await _setSwitch('Appear offline', false);
    await _setSwitch('Show online status', false);
    await goBack();
    await openTab('Chats');
  }

  Future<void> _poll() async {
    final (:alice, :bob, :roomId) = await _openRoom('Poll Room');
    await tapOn(const Key('composer_attach_button'));
    await tapOn(const ValueKey('attach_poll'));
    await waitFor(const ValueKey('poll_question_field'));
    await enterText(const ValueKey('poll_question_field'), 'Which protocol?');
    await enterText(const ValueKey('poll_answer_0'), 'Matrix');
    await enterText(const ValueKey('poll_answer_1'), 'XMPP');
    await tapOn(const ValueKey('poll_hide_results'));
    await tapOn(const ValueKey('poll_create'));
    await waitFor(_bubbleWith('Which protocol?'));

    final content = await bob.latestEvent(
      roomId,
      'org.matrix.msc3381.poll.start',
      senderId: alice.userId,
    );
    final start = content!['org.matrix.msc3381.poll.start']! as Map;
    expect(start['kind'], 'org.matrix.msc3381.poll.undisclosed');
    expect((start['answers']! as List), hasLength(2));

    final option = find.descendant(
      of: find.byType(PollView),
      matching: find.text('Matrix'),
    );
    await waitFor(option);
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tapOn(option);
    await _untilTrue(
      () async =>
          await bob.latestEvent(
            roomId,
            'org.matrix.msc3381.poll.response',
            senderId: alice.userId,
          ) !=
          null,
      timeout: const Duration(seconds: 30),
      reason: 'the vote reaches the homeserver',
    );
    await openTab('Chats');
  }

  Future<void> _topic() async {
    final (:alice, :bob, :roomId) = await _openRoom('Topic Room');
    await tapOn(const Key('chat_overflow_button'));
    await tapOn('Topics');
    await waitFor(const ValueKey('topics_new'));
    await tapOn(const ValueKey('topics_new'));
    await enterText(const ValueKey('topic_title_field'), 'Releases');
    await tapOn(const ValueKey('topic_icon_rocket_launch'));
    await tapOn(const ValueKey('topic_create'));
    // The title shows as soon as the new root reaches the loaded timeline.
    await waitFor(find.text('Sending to # Releases'));

    await enterText(const Key('chat_input_field'), 'first topic reply');
    await tapOn(const Key('send_button'));
    await waitFor(_bubbleWith('first topic reply'));
    await _untilTrue(
      () async => (await bob.threadRootIds(roomId)).isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the homeserver lists the topic as a thread',
    );
    final roots = await bob.threadRootIds(roomId);
    expect(roots, hasLength(1));

    await tapOn(const ValueKey('topic_chip_general'));
    await waitFor(const ValueKey('topic_chip_all'));
    await tapOn(const ValueKey('topic_chip_all'));
    await waitFor(find.text('Releases'));
    await goBack();
    await openTab('Chats');
  }

  Future<void> _disappearing() async {
    final (:alice, :bob, :roomId) = await _openRoom(
      'Disappearing Room',
      aliceCreates: true,
    );
    await tapOn(const Key('chat_overflow_button'));
    await tapOn('Disappearing messages');
    await tapOn(const ValueKey('retention_1'));
    await tapOn(const ValueKey('retention_save'));
    await waitFor('Disappear after 1 day');
    final state = await bob.stateContent(roomId, 'm.room.retention');
    expect(state, {'max_lifetime': 86400000, 'expire_on_clients': true});
    expect(await alice.latestEvent(roomId, 'm.room.redaction'), isNull);
    expect(_bubbleWith('Disappearing Room greeting'), findsOneWidget);
    await openTab('Chats');
  }
}
