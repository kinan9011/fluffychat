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
import 'flows/login_and_chat_backup.dart';
import 'flows/multi_account.dart';
import 'flows/privacy_topics_flows.dart';
import 'flows/scheduling_flows.dart';
import 'flows/shell_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('FluffyChat Integration Tests', () {
    testWidgets('Login and logout flow', loginAndChatBackup);
    testWidgets('Basic Messaging', basicMessaging);
    testWidgets('Shell navigation', shellNavigation);
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
    testWidgets('Final logout', finalLogout);
  });
}
