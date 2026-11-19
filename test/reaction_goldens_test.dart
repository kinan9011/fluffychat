// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';

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

  for (final (brightness, suffix) in [
    (Brightness.light, 'light'),
    (Brightness.dark, 'dark'),
  ]) {
    testWidgets('golden: reactions on both sides, $suffix', (tester) async {
      await harness.open(tester, brightness: brightness);
      await showGoldenConversation(tester, harness);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/chat_reactions_$suffix.png'),
      );
      await harness.finish(tester);
    });
  }
}
