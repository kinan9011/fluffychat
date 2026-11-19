// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';
import 'package:odango/pages/chat_list/chat_list_item.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'shell_navigation.dart';

Future<void> scheduleAndSendNow(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._scheduleAndSendNow());

Future<void> scheduleAndDelete(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._scheduleAndDelete());

Finder _bubbleWith(String text) => find.descendant(
  of: find.byType(MessageBubble),
  matching: find.textContaining(text, findRichText: true),
);

extension on FluffyChatTester {
  Future<({SynapseUser alice, SynapseUser bob, String roomId})> _openRoom(
    String name,
  ) async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(name, invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendText(roomId, '$name greeting');
    final row = find.widgetWithText(ChatListItem, name);
    await waitFor(row);
    await tapOn(row);
    await waitFor(_bubbleWith('$name greeting'));
    return (alice: alice, bob: bob, roomId: roomId);
  }

  /// Types [text], holds send, schedules it for tomorrow morning and opens
  /// the list. The homeserver supports delayed events here, so the server
  /// copy of the sheet is expected.
  Future<void> _scheduleTomorrow(String text) async {
    await enterText(const Key('chat_input_field'), text);
    await longPressOn(const Key('send_button'));
    await waitFor('Schedule message');
    await tapOn('Schedule message');
    await waitFor(const ValueKey('schedule_confirm'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('even if your phone is offline'),
      findsOneWidget,
      reason: 'the homeserver advertises delayed events',
    );
    await tapOn(const ValueKey('schedule_preset_tomorrowMorning'));
    await tapOn(const ValueKey('schedule_confirm'));
    await waitFor(find.textContaining('Scheduled for'));
    await waitFor(const Key('composer_scheduled_button'));
    await tapOn(const Key('composer_scheduled_button'));
    await waitFor(const Key('scheduled_messages_page'));
    await waitFor(text);
  }

  Future<void> _scheduleAndSendNow() async {
    final (:alice, :bob, :roomId) = await _openRoom('Scheduled Send Room');
    const text = 'scheduled hello';
    expect(await alice.delayedEventCount(), 0);
    await _scheduleTomorrow(text);
    expect(await alice.delayedEventCount(), 1);

    await tapOn(text);
    await tapOn(const Key('scheduled_send_now'));
    await waitFor(const Key('scheduled_empty'));
    for (var i = 0; i < 10 && await alice.delayedEventCount() > 0; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect(await alice.delayedEventCount(), 0);

    await tapOn(const Key('scheduled_back'));
    await waitFor(_bubbleWith(text));
    final content = await bob.latestMessageFrom(roomId, alice.userId);
    expect(content['body'], text);
    await openTab('Chats');
  }

  Future<void> _scheduleAndDelete() async {
    final (:alice, :bob, :roomId) = await _openRoom('Scheduled Delete Room');
    const text = 'scheduled to delete';
    await _scheduleTomorrow(text);
    expect(await alice.delayedEventCount(), 1);

    await tapOn(text);
    await tapOn(const Key('scheduled_delete'));
    await waitFor('Delete this scheduled message?');
    await tapOn(const Key('ok_cancel_alert_dialog_ok_button'));
    await waitFor(const Key('scheduled_empty'));
    expect(await alice.delayedEventCount(), 0);

    await tapOn(const Key('scheduled_back'));
    await waitFor(const Key('chat_input_field'));
    expect(_bubbleWith(text), findsNothing);
    await openTab('Chats');
  }
}
