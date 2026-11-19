// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';
import 'utils/reaction_fixtures.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
  });
  tearDown(harness.tearDown);

  testWidgets('golden: reactions on both sides, right to left', (tester) async {
    await harness.open(tester, locale: const Locale('ar'));
    await showGoldenConversation(tester, harness);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat_reactions_rtl.png'),
    );
    await harness.finish(tester);
  });
}
