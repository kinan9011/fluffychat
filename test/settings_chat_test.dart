// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
  });
  tearDown(harness.tearDown);

  Future<void> pumpChatSettings(
    WidgetTester tester, {
    Size size = const Size(400, 1600),
    Locale? locale,
  }) => harness.open(
    tester,
    width: size.width,
    height: size.height,
    locale: locale,
    path: '/settings/chat',
  );

  Finder toggle(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(SettingsToggleRow),
  );

  Future<void> flip(WidgetTester tester, String title) async {
    await tester.ensureVisible(toggle(title));
    await tester.pump();
    await tester.tap(toggle(title));
    await tester.pump();
  }

  const toggles = <(String, AppSettings<bool>)>[
    ('Show folders after spaces', AppSettings.showFoldersAfterSpaces),
    ('Show unread counts on tabs', AppSettings.showTabUnreadCounts),
    ('Hide rooms that are in a space', AppSettings.hideRoomsInSpaces),
    (
      'Unarchive a chat when someone mentions me',
      AppSettings.unarchiveOnMention,
    ),
    ('Formatted messages', AppSettings.renderHtml),
    ('Hide redacted messages', AppSettings.hideRedactedEvents),
    ('Hide invalid or unknown message formats', AppSettings.hideUnknownEvents),
    (
      'Show thumbnails of images and videos',
      AppSettings.showThumbnailsInTimeline,
    ),
    ('Send on enter', AppSettings.sendOnEnter),
    ('Swipe right to left to reply', AppSettings.swipeRightToLeftToReply),
    ('Double-tap to react', AppSettings.doubleTapToReact),
  ];

  group('every toggle writes exactly its own setting', () {
    for (final (title, setting) in toggles) {
      testWidgets(title, (tester) async {
        await pumpChatSettings(tester);
        final before = {for (final (_, other) in toggles) other: other.value};
        final start = setting.value;
        final shown = tester.widget<SettingsToggleRow>(toggle(title)).value;
        expect(shown, start, reason: 'the row shows the real value');
        await flip(tester, title);
        expect(setting.value, !start);
        for (final (otherTitle, other) in toggles) {
          if (identical(other, setting)) continue;
          expect(other.value, before[other], reason: '$otherTitle changed');
        }
        await flip(tester, title);
        expect(setting.value, start);
        await harness.finish(tester);
      });
    }
  });

  group('sections', () {
    testWidgets('three labelled groups, with what each one changes', (
      tester,
    ) async {
      await pumpChatSettings(tester);
      for (final header in ['CHAT LIST', 'MESSAGES', 'WRITING AND REPLYING']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(
        find.text('How your chats are grouped into tabs and folders.'),
        findsOneWidget,
      );
      expect(find.text('How you send, reply and react.'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('custom emojis and stickers are not here', (tester) async {
      await pumpChatSettings(tester);
      expect(find.text('Custom emojis and stickers'), findsNothing);
      expect(find.textContaining('custom emojis or stickers'), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('every old chat setting is still reachable', (tester) async {
      await pumpChatSettings(tester);
      for (final title in [
        'Space navigation',
        'Folders',
        for (final (title, _) in toggles) title,
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      await harness.finish(tester);
    });

    testWidgets('autoplay is not offered on desktop', (tester) async {
      await pumpChatSettings(tester);
      expect(
        find.text('Automatically play animated stickers and emotes'),
        findsNothing,
      );
      await harness.finish(tester);
    });
  });

  testWidgets('space navigation segments write the mode', (tester) async {
    await AppSettings.spaceNavigation.setItem('tabs');
    await pumpChatSettings(tester);
    await tester.tap(find.text('Switcher'));
    await tester.pump();
    expect(
      SpaceNavigationMode.fromSetting(AppSettings.spaceNavigation.value),
      SpaceNavigationMode.switcher,
    );
    await tester.tap(find.text('Tabs'));
    await tester.pump();
    expect(AppSettings.spaceNavigation.value, 'tabs');
    await harness.finish(tester);
  });

  testWidgets('the reaction emoji row only exists while double tap is on', (
    tester,
  ) async {
    await AppSettings.doubleTapToReact.setItem(false);
    await pumpChatSettings(tester);
    expect(find.text('Double-tap reaction'), findsNothing);
    await flip(tester, 'Double-tap to react');
    expect(find.text('Double-tap reaction'), findsOneWidget);
    expect(find.text(AppSettings.doubleTapReaction.value), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('the Folders row opens the folders page', (tester) async {
    await pumpChatSettings(tester);
    await tester.tap(find.byKey(const ValueKey('settings_folders')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.path,
      '/settings/chat/folders',
    );
    await harness.finish(tester);
  });

  group('page level', () {
    testWidgets('a small phone scrolls to the last row without overflow', (
      tester,
    ) async {
      await pumpChatSettings(tester, size: const Size(320, 568));
      await tester.scrollUntilVisible(
        find.text('Double-tap to react'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(toggle('Double-tap to react'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('text at twice the size still reaches the last row', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpChatSettings(tester, size: const Size(320, 568));
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Double-tap to react'),
        200,
        scrollable: scrollable,
      );
      await tester.pump();
      await tester.drag(scrollable, const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(toggle('Double-tap to react'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(scrollable);
      expect(
        scroll.position.pixels,
        scroll.position.maxScrollExtent,
        reason: 'the end of the page is reachable',
      );
      final label = tester.getRect(find.text('Double-tap to react'));
      expect(label.width, lessThanOrEqualTo(320));
      expect(label.height, greaterThan(30), reason: 'the scale is applied');
      await harness.finish(tester);
    });

    testWidgets('a large window shows the page without overflow', (
      tester,
    ) async {
      await pumpChatSettings(tester, size: const Size(1200, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('CHAT LIST'), findsOneWidget);
      await harness.finish(tester);
    });
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
