// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'chat_flows.dart';

Future<void> shellNavigation(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._shellNavigation());

extension ShellFlows on FluffyChatTester {
  Finder get _visibleBar => find.byType(AppBottomBar).hitTestable();

  Future<void> openTab(String label) async {
    final inBar = find.descendant(of: _visibleBar, matching: find.text(label));
    final inRail = find.byTooltip(label).hitTestable();
    if (inBar.evaluate().isEmpty && inRail.evaluate().isEmpty) await goBack();
    await tapOn(inBar.evaluate().isNotEmpty ? inBar : inRail);
  }

  Finder get _chatsBadge => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        RegExp(r'^Chats, \d+ unread$').hasMatch(widget.properties.label ?? ''),
  );

  static const _bobChatName = 'Bob says hi';

  Future<void> _bobMessagesAlice() async {
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(_bobChatName, invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendText(roomId, 'ping');
    await bob.logout();
    await alice.logout();
  }

  Future<void> _shellNavigation() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();

    expect(_chatsBadge, findsNothing, reason: 'nothing unread yet');
    await _bobMessagesAlice();
    await waitFor(_bobChatName);
    await waitFor(_chatsBadge);

    await tapOn(_bobChatName);
    await waitFor(find.byKey(const Key('chat_input_field')));
    await tester.pump(const Duration(seconds: 3));
    await goBack();
    await waitForGone(_chatsBadge);

    await openTab('Calls');
    await waitFor('Ongoing group calls');
    await openTab('Profile');
    await waitFor('Accounts');
    await openTab('Settings');
    await waitFor('Chat backup');
    await openTab('Chats');
    await waitFor(ChatFlows.groupChatName);

    await tapOn(ChatFlows.groupChatName);
    await waitFor(find.byKey(const Key('chat_input_field')));
    final onPhone = find.byType(AppBottomBar).evaluate().isNotEmpty;
    if (onPhone) {
      expect(_visibleBar, findsNothing, reason: 'a chat covers the bar');
      await goBack();
      expect(_visibleBar, findsOneWidget);
      return;
    }
    await openTab('Settings');
    await waitFor('Chat backup');
    await openTab('Chats');
    await waitFor(find.byKey(const Key('chat_input_field')));
  }
}
