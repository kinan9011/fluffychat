// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/space_switcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'chat_flows.dart';
import 'shell_navigation.dart';

Future<void> chatListTabs(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._chatListTabs());

Future<void> chatListFolders(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._chatListFolders());

Future<void> chatListSwipeArchive(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._chatListSwipeArchive());

Future<void> chatListPeek(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._chatListPeek());

Future<void> chatListDraft(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._chatListDraft());

extension on FluffyChatTester {
  static const _spaceName = 'Test Space 01';
  static const _peekRoomName = 'Peek flow room';
  static const _peekMessage = 'peek me';
  static const _draftText = 'draft text kept for later';
  static const _folderName = 'Work';

  Finder get _groupRow =>
      find.widgetWithText(ChatListItem, ChatFlows.groupChatName);

  Future<void> _swipeLeft(Finder row) async {
    await tester.drag(row, const Offset(-250, 0));
    await tester.pumpAndSettle();
  }

  Future<void> _setSpaceNavigation(String label) async {
    await openTab('Settings');
    await tapOn('Chat');
    await tapOn(label);
    await openTab('Chats');
  }

  Future<void> _chatListTabs() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();
    await openTab('Chats');

    await tapOn(const Key('accounts_and_settings_buttons'));
    await tapOn(find.widgetWithText(PopupMenuItem<Object>, 'New space'));
    await enterText(TextField, _spaceName);
    await tapOn(find.widgetWithText(ElevatedButton, 'New space'));
    await waitFor(find.widgetWithText(InkWell, _spaceName));
    await waitFor(ChatFlows.groupChatName);

    await longPressOn(find.widgetWithText(InkWell, _spaceName));
    await tapOn('Space overview');
    await tester.pump(const Duration(seconds: 3));
    await goBack();
    await waitFor(ChatFlows.groupChatName);

    await longPressOn(ChatFlows.groupChatName);
    await waitFor(
      "Peeking: ${ChatFlows.groupChatName} won't see that you read this",
    );
    await tapOn('More options');
    await tapOn('More');
    await tapOn('Add to space');
    await tapOn(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text(_spaceName),
      ),
    );
    await waitFor(find.widgetWithText(InkWell, _spaceName));

    await tapOn(find.widgetWithText(InkWell, _spaceName));
    await waitFor(ChatFlows.groupChatName);
    expect(find.byType(ChatListItem), findsOneWidget, reason: 'space filter');
    await tapOn('All chats');

    await _setSpaceNavigation('Switcher');
    await tapOn(SpaceSwitcherChip);
    await waitFor('SWITCH SPACE');
    expect(find.text(_spaceName), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _setSpaceNavigation('Tabs');
  }

  Future<void> _chatListFolders() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();

    await openTab('Settings');
    await tapOn('Chat');
    await tapOn('Folders');
    await tapOn('Create folder');
    await enterText(find.byKey(const ValueKey('folder_name')), _folderName);
    await tapOn(find.widgetWithText(CheckboxListTile, 'Groups'));
    await tapOn(find.byKey(const ValueKey('save_folder')));
    await waitFor(find.widgetWithText(ListTile, _folderName));

    final alice = await SynapseUser.login(user1Name, user1Pw);
    final stored = await alice.getAccountData('im.fluffychat.folders');
    await alice.logout();
    final folders = (stored! as Map)['folders'] as List;
    expect((stored as Map)['version'], 1);
    expect(folders.map((f) => (f as Map)['name']), [_folderName]);

    await goBack();
    await goBack();
    await openTab('Chats');
    final tab = find.widgetWithText(InkWell, _folderName);
    await waitFor(tab);
    await tester.ensureVisible(tab);
    await tapOn(tab);
    await waitFor(ChatFlows.groupChatName);
    expect(_groupRow, findsOneWidget, reason: 'Groups filter keeps the group');

    await longPressOn(tab);
    await tapOn('Edit folder');
    await tapOn(find.widgetWithText(CheckboxListTile, 'Groups'));
    await tapOn(find.widgetWithText(CheckboxListTile, 'Personal'));
    await tapOn(find.byKey(const ValueKey('save_folder')));
    await waitFor(find.widgetWithText(ListTile, _folderName));
    await goBack();
    await goBack();
    await openTab('Chats');
    await waitFor(tab);
    await waitForGone(_groupRow);
    expect(_groupRow, findsNothing, reason: 'a Personal folder drops groups');

    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await longPressOn(tab);
    await waitFor('Delete folder');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await openTab('Settings');
    await tapOn('Chat');
    await tapOn('Folders');
    await tapOn(find.widgetWithText(ListTile, _folderName));
    await tapOn(find.byKey(const ValueKey('delete_folder')));
    await tapOn(find.widgetWithText(TextButton, 'Delete').last);
    await waitForGone(find.widgetWithText(ListTile, _folderName));
    await goBack();
    await goBack();
    await openTab('Chats');
    await tapOn('All chats');
  }

  Future<void> _chatListSwipeArchive() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();
    await openTab('Chats');
    await waitFor(_groupRow);

    await _swipeLeft(_groupRow);
    await tapOn('Archive');
    await waitForGone(_groupRow);
    await waitFor('Archived chats');

    await tapOn('Archived chats');
    await waitFor(_groupRow);
    await _swipeLeft(_groupRow);
    await tapOn('Unarchive');
    await waitFor(_groupRow);
    await waitForGone('Archived chats');
  }

  Future<void> _chatListPeek() async {
    await ensureLoggedIn();
    await openTab('Chats');

    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(_peekRoomName, invite: [alice.userId]);
    await alice.join(roomId);
    final eventId = await bob.sendText(roomId, _peekMessage);

    final row = find.widgetWithText(ChatListItem, _peekRoomName);
    final badge = find.descendant(of: row, matching: find.text('1'));
    const notice = "Peeking: $_peekRoomName won't see that you read this";
    await waitFor(row);
    await waitFor(badge);
    final fullyReadBefore = await alice.getRoomAccountData(
      roomId,
      'm.fully_read',
    );

    await longPressOn(row);
    await waitFor(notice);
    await waitFor(_peekMessage);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await waitForGone(notice);
    await tester.pump(const Duration(seconds: 6));

    expect(
      await alice.getRoomAccountData(roomId, 'm.fully_read'),
      fullyReadBefore,
      reason: 'peeking does not move the fully read marker',
    );
    expect(
      await bob.receiptUsers(roomId, eventId),
      isNot(contains(alice.userId)),
      reason: 'bob sees no receipt of alice',
    );
    expect(
      await alice.receiptUsers(roomId, eventId),
      isNot(contains(alice.userId)),
      reason: 'alice has no private receipt either',
    );
    expect(badge, findsOneWidget, reason: 'the chat is still unread');

    // The row takes taps after a peek (the Navigator's pointer cancel arrives).
    // Opening the chat is the control: it sends the receipt, so the checks
    // above would have noticed one. Public receipts are off by default, so the
    // receipt is the private one: only alice sees it, bob never does.
    await tapOn(row);
    await waitFor(find.byKey(const Key('chat_input_field')));
    final end = DateTime.now().add(const Duration(seconds: 30));
    var seen = false;
    while (!seen && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(seconds: 1));
      seen = (await alice.receiptUsers(roomId, eventId)).contains(alice.userId);
    }
    expect(seen, isTrue, reason: 'opening the chat sends the private receipt');
    expect(
      await bob.receiptUsers(roomId, eventId),
      isNot(contains(alice.userId)),
      reason: 'with public receipts off bob never sees it',
    );
    expect(
      await alice.getRoomAccountData(roomId, 'm.fully_read'),
      isNot(fullyReadBefore),
    );
    await goBack();

    // Second peek, "Mark as read" in its menu is the one explicit way too.
    await bob.sendText(roomId, 'second');
    await waitFor(badge);
    await longPressOn(row);
    await waitFor(notice);
    await tapOn('Mark as read');
    await waitForGone(badge);
    await bob.logout();
    await alice.logout();
  }

  Future<void> _chatListDraft() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();
    await openTab('Chats');

    await tapOn(ChatFlows.groupChatName);
    await enterText(const Key('chat_input_field'), _draftText);
    await tester.pump(const Duration(seconds: 2));
    await goBack();
    await waitFor(find.textContaining('Draft: $_draftText'));

    await tapOn(ChatFlows.groupChatName);
    await tapOn(const Key('send_button'));
    await waitFor(_draftText);
    await goBack();
    await waitForGone(find.textContaining('Draft:'));
  }
}
