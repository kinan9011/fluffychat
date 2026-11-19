// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/space_overview/community_widgets.dart';

import '../utils/fluffy_chat_tester.dart';
import 'auth_flows.dart';
import 'shell_navigation.dart';

Future<void> communityFlow(WidgetTester widgetTester) =>
    widgetTester.startFluffyChatTest().then((tester) => tester._community());

extension on FluffyChatTester {
  static const _spaceName = 'Test Space 02';

  /// An admin adds an announcements room to a space: the overview turns into
  /// a community with the announcements card and the note that only
  /// moderators and admins can post.
  Future<void> _community() async {
    await ensureLoggedIn();
    await openTab('Chats');
    await tapOn(const Key('accounts_and_settings_buttons'));
    await tapOn(find.widgetWithText(PopupMenuItem<Object>, 'New space'));
    await enterText(TextField, _spaceName);
    await tapOn(find.widgetWithText(ElevatedButton, 'New space'));
    await waitFor(find.widgetWithText(InkWell, _spaceName));

    await longPressOn(find.widgetWithText(InkWell, _spaceName));
    await tapOn('Space overview');
    await waitFor('Joined 0');
    expect(find.byType(CommunityBanner), findsNothing);

    await tapOn(find.byType(PopupMenuButton<void>));
    await tapOn('Add announcements room');
    await waitFor(
      'Matrix has no broadcast channels. This creates a normal group where only moderators and admins can post.',
    );
    await tapOn('Add announcements room', index: 1);
    await waitFor(find.byType(AnnouncementsCard));
    await waitFor('Only moderators and admins can post');
    await waitFor('GROUPS IN THIS COMMUNITY');
    await goBack();
    await openTab('Chats');
  }
}
