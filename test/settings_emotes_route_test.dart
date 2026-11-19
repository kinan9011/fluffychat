// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/settings_emotes/settings_emotes.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
  });
  tearDown(harness.tearDown);

  String location() =>
      FluffyChatApp.router.routeInformationProvider.value.uri.path;

  testWidgets('Settings opens Emotes and stickers at its own path', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings');
    await tester.tap(find.text('Emotes and stickers'));
    await harness.settle(tester, rounds: 3);
    expect(location(), '/settings/emotes');
    expect(find.byType(EmotesSettings), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('the old path under Chat settings redirects', (tester) async {
    await harness.open(tester, path: '/settings/chat/emotes');
    expect(location(), '/settings/emotes');
    expect(find.byType(EmotesSettings), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('back from Emotes and stickers lands on Settings', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings');
    await tester.tap(find.text('Emotes and stickers'));
    await harness.settle(tester, rounds: 3);
    FluffyChatApp.router.go('/settings');
    await harness.settle(tester, rounds: 3);
    expect(location(), '/settings');
    expect(find.byType(EmotesSettings), findsNothing);
    await harness.finish(tester);
  });
}
