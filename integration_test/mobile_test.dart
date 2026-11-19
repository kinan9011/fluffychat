// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'flows/auth_flows.dart';
import 'flows/basic_messaging.dart';
import 'flows/chat_flows.dart';
import 'flows/chat_list_flows.dart';
import 'flows/composer_flows.dart';
import 'flows/conversation_flows.dart';
import 'flows/direct_chat_flows.dart';
import 'flows/login_and_chat_backup.dart';
import 'flows/multi_account.dart';
import 'flows/privacy_topics_flows.dart';
import 'flows/scheduling_flows.dart';
import 'flows/search_flows.dart';
import 'flows/settings_flows.dart';
import 'flows/shell_navigation.dart';
import 'flows/space_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('FluffyChat Integration Tests', () {
    testWidgets('Login and logout flow', loginAndChatBackup);
    testWidgets('Basic Messaging', basicMessaging);
    testWidgets('Shell navigation', shellNavigation);
    testWidgets('Calls hidden without a call service', callsHiddenFlow);
    testWidgets('Chat list tabs', chatListTabs);
    testWidgets('Chat list folders', chatListFolders);
    testWidgets('Chat list swipe and archive', chatListSwipeArchive);
    testWidgets('Chat list peek', chatListPeek);
    testWidgets('Chat list draft', chatListDraft);
    testWidgets('Conversation shell', conversationShell);
    testWidgets('Conversation bubbles', conversationBubbles);
    testWidgets('Conversation jump buttons', conversationJumpButtons);
    testWidgets('Composer rich text', composerRichText);
    testWidgets('Edit history', editHistory);
    testWidgets('Scheduled message send now', scheduleAndSendNow);
    testWidgets('Scheduled message delete', scheduleAndDelete);
    testWidgets('Multi-Account', multiAccount);
    testWidgets('Archive chats', archiveChats);
    // After the flows that look for older chats by name: these create rooms.
    testWidgets('Appear offline', appearOfflineFlow);
    testWidgets('Poll creation', pollFlow);
    testWidgets('Topics', topicFlow);
    testWidgets('Disappearing messages', disappearingFlow);
    testWidgets('Direct chat with the default timer', directChatFlow);
    testWidgets('Search encrypted chats', searchEncryptedFlow);
    testWidgets('Search unencrypted chats', searchServerFlow);
    testWidgets('Search index wiped on logout', searchWipeFlow);
    testWidgets('Space community', communityFlow);
    testWidgets('Settings appearance', settingsAppearanceFlow);
    testWidgets('Settings chat', settingsChatFlow);
    testWidgets('Settings homeserver features', settingsHomeserverFlow);
    testWidgets('Settings export chat', settingsExportFlow);
    // Signs out every other session of the user: keep it after the flows that
    // use sessions of their own.
    testWidgets('Settings linked devices', settingsLinkedDevicesFlow);
    testWidgets('Final logout', finalLogout);
  });
}
