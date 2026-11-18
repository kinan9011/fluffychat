// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';
import '../utils/synapse_api.dart';
import 'auth_flows.dart';
import 'shell_navigation.dart';

/// Starts a direct chat through the UI with the default settings. The unit
/// tests cannot catch a bug in what the app hands to the SDK's
/// `startDirectChat`, so this flow checks what the homeserver really got.
Future<void> directChatFlow(WidgetTester widgetTester) => widgetTester
    .startFluffyChatTest()
    .then((tester) => tester._directChatDefaultTimer());

extension on FluffyChatTester {
  Future<void> _directChatDefaultTimer() async {
    await ensureLoggedIn();
    await openTab('Chats');
    final alice = await SynapseUser.login(user1Name, user1Pw);
    final bob = await SynapseUser.login(user2Name, user2Pw);
    await bob.uploadDeviceKeys();
    expect(await alice.directRoomWith(bob.userId), isNull);

    await tapOn(find.byIcon(Icons.edit_square));
    await waitFor('New message');
    expect(find.text('New group'), findsOneWidget);
    expect(find.text('New space'), findsOneWidget);
    expect(find.text('Share my invite link'), findsOneWidget);
    await enterText(find.byType(TextField).first, bob.userId);
    await tester.pump(const Duration(seconds: 2));
    final result = find.widgetWithText(InkWell, bob.userId);
    await waitFor(result);
    await tapOn(result);
    await waitFor('Create new chat');
    await tapOn('Create new chat');

    final end = DateTime.now().add(const Duration(seconds: 60));
    Map<String, Map<String, Object?>>? state;
    while (state == null) {
      state = await alice.directRoomWith(bob.userId);
      if (state != null) break;
      if (DateTime.now().isAfter(end)) {
        throw Exception('Timed out: the direct chat was not created');
      }
      await tester.pump(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect(
      state['m.room.encryption']?['algorithm'],
      'm.megolm.v1.aes-sha2',
      reason: 'a direct chat with someone who has keys is encrypted',
    );
    expect(
      state.containsKey('m.room.retention'),
      isFalse,
      reason: 'the default timer is off: nothing is sent',
    );
    await openTab('Chats');
  }
}
