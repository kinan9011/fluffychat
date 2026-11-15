// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
  });

  Future<void> pumpChatSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    FluffyChatApp.router.go('/settings/chat');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Space navigation section writes the three settings', (
    tester,
  ) async {
    await AppSettings.spaceNavigation.setItem('tabs');
    await AppSettings.showFoldersAfterSpaces.setItem(true);
    await AppSettings.showTabUnreadCounts.setItem(true);
    await pumpChatSettings(tester);

    expect(find.text('Space navigation'), findsOneWidget);
    await tester.tap(find.text('Switcher'));
    await tester.pump();
    expect(
      SpaceNavigationMode.fromSetting(AppSettings.spaceNavigation.value),
      SpaceNavigationMode.switcher,
    );

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Show folders after spaces'),
    );
    await tester.pump();
    expect(AppSettings.showFoldersAfterSpaces.value, isFalse);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Show unread counts on tabs'),
    );
    await tester.pump();
    expect(AppSettings.showTabUnreadCounts.value, isFalse);

    await tester.tap(find.text('Tabs'));
    await tester.pump();
    expect(AppSettings.spaceNavigation.value, 'tabs');
    await tester.pump(const Duration(seconds: 35));
  });

  testWidgets('Unarchive on mention is off and the switch writes it', (
    tester,
  ) async {
    await AppSettings.unarchiveOnMention.setItem(false);
    await pumpChatSettings(tester);
    final tile = find.widgetWithText(
      SwitchListTile,
      'Unarchive a chat when someone mentions me',
    );
    await tester.ensureVisible(tile);
    expect(find.text('Off: archived chats stay archived.'), findsOneWidget);
    await tester.tap(tile);
    await tester.pump();
    expect(AppSettings.unarchiveOnMention.value, isTrue);
    await tester.tap(tile);
    await tester.pump();
    expect(AppSettings.unarchiveOnMention.value, isFalse);
    await tester.pump(const Duration(seconds: 35));
  });

  test(
    'new settings default to tabs, folders shown and counts shown',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.reset(loadWebConfigFile: false);
      expect(AppSettings.spaceNavigation.value, 'tabs');
      expect(AppSettings.showFoldersAfterSpaces.value, isTrue);
      expect(AppSettings.showTabUnreadCounts.value, isTrue);
    },
  );
}
