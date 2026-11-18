// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/events/message_bubble.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/global_search/global_search_view.dart';
import 'package:fluffychat/pages/global_search/search_filter_sheet.dart';
import 'package:fluffychat/pages/global_search/search_result_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'chat_flows.dart';
import 'shell_navigation.dart';

Future<void> searchEncryptedFlow(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._searchEncrypted());

Future<void> searchServerFlow(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._searchServer());

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

  Future<void> _openSearch() async {
    await openTab('Chats');
    await tapOn(find.byTooltip('Search'));
    await waitFor(GlobalSearchView.fieldKey);
  }

  Future<void> _leaveSearch() async {
    await tapOn(GlobalSearchView.cancelKey);
    await openTab('Chats');
  }

  /// A message of an encrypted chat is found through the index on this
  /// device and opens the chat.
  Future<void> _searchEncrypted() async {
    await ensureLoggedIn();
    await ensureGroupChatCreated();
    await openTab('Chats');
    final word = 'needle${DateTime.now().millisecondsSinceEpoch}';
    await tapOn(ChatFlows.groupChatName);
    await enterText(const Key('chat_input_field'), 'find me $word');
    await tapOn(const Key('send_button'));
    await waitFor(
      find.descendant(
        of: find.byType(MessageBubble),
        matching: find.textContaining(word, findRichText: true),
      ),
    );
    await goBack();

    await _openSearch();
    await enterText(GlobalSearchView.fieldKey, word);
    await waitFor(find.byType(MessageHitTile));
    expect(
      find.textContaining('Encrypted chats are searched on this device only.'),
      findsOneWidget,
    );
    await tapOn(find.byType(MessageHitTile));
    await waitFor(const Key('chat_input_field'));
    await goBack();
    await openTab('Chats');
  }

  /// A message of an unencrypted chat is found by the server of the user,
  /// the filter sheet applies and resets.
  Future<void> _searchServer() async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final word = 'haystack${DateTime.now().millisecondsSinceEpoch}';
    final roomId = await bob.createRoom('Search Room', invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendText(roomId, 'find $word');
    await waitFor(find.widgetWithText(ChatListItem, 'Search Room'));

    await _openSearch();
    await tapOn(GlobalSearchView.filtersKey);
    await waitFor('Filters');
    await tapOn(
      find.descendant(
        of: find.byType(SearchFilterSheet),
        matching: find.text('Files'),
      ),
    );
    await tapOn(SearchFilterSheet.applyKey);
    expect(
      tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
      isTrue,
      reason: 'one filter group is active',
    );
    await tapOn(GlobalSearchView.filtersKey);
    await tapOn(SearchFilterSheet.resetKey);
    await tapOn(SearchFilterSheet.applyKey);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

    var attempt = 0;
    await _untilTrue(() async {
      attempt++;
      await enterText(
        GlobalSearchView.fieldKey,
        attempt.isEven ? word : '$word ',
      );
      await tester.pump(const Duration(seconds: 2));
      return find.byType(MessageHitTile).evaluate().isNotEmpty;
    }, reason: 'the server search found the message');
    await waitFor('Messages in unencrypted chats are searched on your server.');
    await _leaveSearch();
  }
}
