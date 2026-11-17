// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/chat_jump_buttons.dart';
import 'package:fluffychat/pages/chat/events/message_bubble.dart';
import 'package:fluffychat/pages/chat/events/message_footer.dart';
import 'package:fluffychat/pages/chat/events/reaction_bar.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'chat_flows.dart';
import 'shell_navigation.dart';

Future<void> conversationShell(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._conversationShell());

Future<void> conversationBubbles(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._conversationBubbles());

Future<void> conversationJumpButtons(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._conversationJumpButtons());

const _overflow = Key('chat_overflow_button');

Finder _inBubble(String text) =>
    find.descendant(of: find.byType(MessageBubble), matching: find.text(text));
const _bubblesRoom = 'Conversation Bubbles Room';
const _jumpRoom = 'Conversation Jump Room';

extension on FluffyChatTester {
  Future<void> _sendMessage(String text) async {
    // The helper unfocuses the field after typing, a second enterText needs
    // the field focused again like a user's tap does.
    await tapOn(const Key('chat_input_field'));
    await enterText(const Key('chat_input_field'), text);
    await tapOn(const Key('send_button'));
    await waitFor(
      find.descendant(
        of: find.byType(MessageBubble),
        matching: find.text(text),
      ),
    );
    // Typing while the server still answers the send loses the new text: wait
    // until the message shows as sent.
    await waitForGone(
      find.descendant(
        of: find.byType(MessageFooter),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> _openOverflow() async {
    await tapOn(_overflow);
    await waitFor('Change wallpaper');
  }

  Future<void> _closeOverflow() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await waitForGone('Change wallpaper');
  }

  Future<void> _conversationShell() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();
    await tapOn(ChatFlows.groupChatName);
    await waitFor(_overflow);
    expect(
      find.descendant(
        of: find.byKey(const Key('chat_page')),
        matching: find.byType(BackButton),
      ),
      findsOneWidget,
    );

    await _sendMessage('shell one');
    await _sendMessage('shell two');
    expect(find.byKey(ChatJumpButtons.scrollDownKey), findsNothing);

    await _openOverflow();
    for (final label in [
      'Mute',
      'Search',
      'Scheduled messages',
      'Change wallpaper',
      'Leave chat',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Clear history'), findsNothing);
    await _closeOverflow();

    await _openOverflow();
    await tapOn('Mute');
    await _openOverflow();
    expect(find.text('Unmute'), findsOneWidget, reason: 'muted now');
    await tapOn('Unmute');
    await _openOverflow();
    expect(find.text('Mute'), findsOneWidget, reason: 'unmuted again');
    await _closeOverflow();

    await _openOverflow();
    await tapOn('Search');
    await waitFor(find.byType(TextField));
    await goBack();
    await waitFor(_overflow);
    await goBack();
  }

  Future<void> _conversationBubbles() async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(_bubblesRoom, invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendText(roomId, 'bubble from bob');

    final row = find.widgetWithText(ChatListItem, _bubblesRoom);
    await waitFor(row);
    await tapOn(row);
    await waitFor(_inBubble('bubble from bob'));

    // Long press opens the reaction bar and the menu, and selects nothing.
    await longPressOn(_inBubble('bubble from bob'));
    await waitFor(find.byType(ReactionBar));
    await waitFor('Reply');
    await waitFor('Message info');
    expect(find.byTooltip('Copy to clipboard'), findsNothing);

    // Reacting closes the menu and shows the reaction under the bubble.
    await tapOn('👍');
    await waitForGone(find.byType(ReactionBar));
    await waitFor('👍');

    // Reply puts the quote above the composer and into the next bubble.
    await longPressOn(_inBubble('bubble from bob'));
    await tapOn('Reply');
    await _sendMessage('my reply to bob');

    // Select starts multi-select and shows the selection toolbar.
    await longPressOn(_inBubble('my reply to bob'));
    await tapOn('Select');
    await waitFor(find.byTooltip('Copy to clipboard'));
    await tapOn(find.byTooltip('Close'));
    await waitForGone(find.byTooltip('Copy to clipboard'));

    await goBack();
    await bob.logout();
    await alice.logout();
  }

  Future<void> _conversationJumpButtons() async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(_jumpRoom, invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendMany(roomId, 40, 'filler');

    final row = find.widgetWithText(ChatListItem, _jumpRoom);
    await waitFor(row);
    await tapOn(row);
    await waitFor('filler 40');
    expect(find.byKey(ChatJumpButtons.scrollDownKey), findsNothing);

    // Scrolled up, the chat sends no read marker for what arrives next: this
    // is where the mention button earns its place.
    final chat = find.byKey(const Key('chat_page'));
    for (var i = 0; i < 6; i++) {
      await tester.drag(chat, const Offset(0, 700));
      await tester.pumpAndSettle();
    }
    await waitFor(find.byKey(ChatJumpButtons.scrollDownKey));
    final fullyRead = await alice.getRoomAccountData(roomId, 'm.fully_read');

    final mentionId = await bob.sendMention(roomId, 'ping alice', alice.userId);
    await bob.sendMany(roomId, 30, 'later');
    await waitFor(find.byKey(ChatJumpButtons.mentionKey));
    expect(
      find.descendant(
        of: find.byKey(ChatJumpButtons.mentionKey),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tapOn(find.byKey(ChatJumpButtons.mentionKey));
    await waitFor(find.byKey(Key('mention_ring_$mentionId')));
    await waitForGone(find.byKey(ChatJumpButtons.mentionKey));
    await tester.pump(const Duration(seconds: 3));
    expect(
      await alice.getRoomAccountData(roomId, 'm.fully_read'),
      fullyRead,
      reason: 'jumping to a mention moves no read marker',
    );

    await tapOn(find.byKey(ChatJumpButtons.scrollDownKey));
    await waitFor('later 30');
    await waitForGone(find.byKey(ChatJumpButtons.scrollDownKey));

    await goBack();
    await waitFor(find.byType(ChatList));
    await bob.logout();
    await alice.logout();
  }
}
