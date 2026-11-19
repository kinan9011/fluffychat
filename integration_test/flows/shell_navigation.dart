// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/fluffy_chat_app.dart';
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

Future<void> callsHiddenFlow(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._callsHidden());

extension ShellFlows on FluffyChatTester {
  Finder get _visibleBar => find.byType(AppBottomBar).hitTestable();

  Future<void> openTab(String label) async {
    final inBar = find.descendant(of: _visibleBar, matching: find.text(label));
    final inRail = find.byTooltip(label).hitTestable();
    if (inBar.evaluate().isEmpty && inRail.evaluate().isEmpty) await goBack();
    await tapOn(inBar.evaluate().isNotEmpty ? inBar : inRail);
  }

  /// The Synapse of the integration tests has no call service, so no Calls
  /// tab is offered anywhere.
  void _expectNoCallsTab() {
    expect(
      find.descendant(of: _visibleBar, matching: find.text('Calls')),
      findsNothing,
    );
    expect(find.byTooltip('Calls'), findsNothing);
  }

  Future<void> _callsHidden() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();
    await openTab('Chats');
    await waitFor(ChatFlows.groupChatName);
    _expectNoCallsTab();

    FluffyChatApp.router.go('/calls');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.path,
      '/rooms',
      reason: 'the Calls route is deactivated',
    );
    await waitFor(ChatFlows.groupChatName);

    await tapOn(ChatFlows.groupChatName);
    await waitFor(find.byKey(const Key('chat_input_field')));
    await tapOn(const Key('chat_overflow_button'));
    await waitFor('Mute');
    expect(find.text('Video call'), findsNothing);
    expect(find.byIcon(Icons.videocam_rounded), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 1));
    await goBack();

    await openTab('Settings');
    await scrollUntilVisible('Homeserver');
    await tapOn('Homeserver');
    await waitFor('Group calls');
    await goBack();
    await openTab('Chats');
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

    _expectNoCallsTab();
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
