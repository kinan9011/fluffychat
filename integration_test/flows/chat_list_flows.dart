// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/space_switcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/fluffy_chat_tester.dart';
import 'auth_flows.dart';
import 'chat_flows.dart';
import 'shell_navigation.dart';

Future<void> chatListTabs(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._chatListTabs());

extension on FluffyChatTester {
  static const _spaceName = 'Test Space 01';

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
}
