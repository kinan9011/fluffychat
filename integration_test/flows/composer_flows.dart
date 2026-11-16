// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/composer/format_panel.dart';
import 'package:fluffychat/pages/chat/edit_history_sheet.dart';
import 'package:fluffychat/pages/chat/events/message_bubble.dart';
import 'package:fluffychat/pages/chat/events/message_footer.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'shell_navigation.dart';

Future<void> composerRichText(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._composerRichText());

Future<void> editHistory(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._editHistory());

const _composerRoom = 'Composer Rich Room';
const _historyRoom = 'Edit History Room';

Finder _bubbleWith(String text) => find.descendant(
  of: find.byType(MessageBubble),
  matching: find.textContaining(text, findRichText: true),
);

extension on FluffyChatTester {
  ChatController get _chat =>
      tester.state<ChatController>(find.byType(ChatPageWithRoom));

  void _select(String text, String word) {
    final start = text.indexOf(word);
    final composer = _chat.sendController;
    composer.value = composer.value.copyWith(
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + word.length,
      ),
    );
  }

  Future<void> _waitSent() async {
    await waitForGone(
      find.descendant(
        of: find.byType(MessageFooter),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> _composerRichText() async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(_composerRoom, invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendText(roomId, 'composer greeting');

    final row = find.widgetWithText(ChatListItem, _composerRoom);
    await waitFor(row);
    await tapOn(row);
    await waitFor(_bubbleWith('composer greeting'));

    const text = 'hello world';
    await enterText(const Key('chat_input_field'), text);
    await tapOn(const Key('composer_format_toggle'));
    await waitFor(find.byType(FormatPanel));

    _select(text, 'world');
    await tester.pump();
    await tapOn(const ValueKey('format_bold'));

    _select(text, 'hello');
    await tester.pump();
    await tapOn(const ValueKey('format_link'));
    await waitFor('Add link');
    final field = find.byType(TextField).last;
    await enterText(field, 'javascript:alert(1)');
    await tapOn('Ok');
    await waitFor('Invalid url');
    // A second enterText does not reach the dialog field once the first
    // attempt failed validation, so the controller is set directly.
    tester.widget<TextField>(field).controller!.text = 'https://example.org';
    await tester.pumpAndSettle();
    await tapOn('Ok');
    await waitForGone('Add link');

    await tapOn(const Key('send_button'));
    await waitFor(_bubbleWith('world'));
    await _waitSent();

    final content = await bob.latestMessageFrom(roomId, alice.userId);
    expect(content['format'], 'org.matrix.custom.html');
    final html = content['formatted_body']! as String;
    expect(html, contains('<strong>world</strong>'));
    expect(html, contains('<a href="https://example.org">hello</a>'));
    expect(html, isNot(contains('javascript')));
    expect(content['body'], '[hello](https://example.org) **world**');

    await tapOn(const Key('chat_input_field'));
    await enterText(const Key('chat_input_field'), 'plain *markdown* text');
    await tapOn(const Key('send_button'));
    await waitFor(_bubbleWith('markdown'));
    await _waitSent();
    final plain = await bob.latestMessageFrom(roomId, alice.userId);
    expect(plain['formatted_body'], contains('<em>markdown</em>'));
    expect(plain['body'], 'plain *markdown* text');

    await tapOn(const Key('chat_input_field'));
    await enterText(const Key('chat_input_field'), 'draft stays encrypted');
    await tester.pump(const Duration(seconds: 2));
    await goBack();
    await waitFor(find.textContaining('Draft: draft stays encrypted'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) => key.startsWith('draft_')), isEmpty);

    await tapOn(row);
    await tapOn(const Key('send_button'));
    await waitFor(_bubbleWith('draft stays encrypted'));
    await _waitSent();
    await goBack();
    await waitForGone(find.textContaining('Draft:'));
  }

  Future<void> _sendComposed(String text, String shownText) async {
    await tapOn(const Key('chat_input_field'));
    await enterText(const Key('chat_input_field'), text);
    await tapOn(const Key('send_button'));
    await waitFor(_bubbleWith(shownText));
    await _waitSent();
  }

  Future<void> _editHistory() async {
    await ensureLoggedIn();
    await openTab('Chats');
    final bob = await SynapseUser.login(user2Name, user2Pw);
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final roomId = await bob.createRoom(_historyRoom, invite: [alice.userId]);
    await alice.join(roomId);
    await bob.sendText(roomId, 'history greeting');

    final row = find.widgetWithText(ChatListItem, _historyRoom);
    await waitFor(row);
    await tapOn(row);
    await waitFor(_bubbleWith('history greeting'));

    const first = 'Testing it now, results in an hour.';
    const second = 'Testing it now, results in 20 minutes.';
    const third = 'Testing it now, results in 15 minutes.';
    await _sendComposed(first, first);
    expect(find.byKey(const ValueKey('edited_label')), findsNothing);

    await longPressOn(_bubbleWith(first));
    await tapOn('Edit');
    await _sendComposed(second, second);
    await waitFor(find.byKey(const ValueKey('edited_label')));

    await longPressOn(_bubbleWith(second));
    await tapOn('Edit');
    await _sendComposed(third, third);
    await tester.pump(const Duration(seconds: 1));

    await tapOn(find.byKey(const ValueKey('edited_label')));
    await waitFor('Edit history');
    // The sheet slides in: tapping while it moves would miss its buttons.
    await tester.pump(const Duration(seconds: 1));
    await waitFor(find.textContaining('CURRENT'));
    await waitFor(find.textContaining('ORIGINAL'));
    Finder inSheet(String text) => find.descendant(
      of: find.byType(EditHistorySheet),
      matching: find.text(text, findRichText: true),
    );
    await waitFor(inSheet(first));
    await waitFor(inSheet(third));
    expect(find.textContaining('EDITED'), findsWidgets);

    await tapOn(find.byKey(const ValueKey('edit_history_close')));
    await waitForGone('Edit history');

    await longPressOn(_bubbleWith(third));
    await waitFor('Edit history');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await goBack();
    await waitFor(row);
  }
}
