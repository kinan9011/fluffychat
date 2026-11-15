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

extension on FluffyChatTester {
  static const _spaceName = 'Test Space 01';
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
}
