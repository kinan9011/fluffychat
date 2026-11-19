// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
  });
  tearDown(harness.tearDown);

  testWidgets('chat settings mirror in right to left without overflow', (
    tester,
  ) async {
    await harness.open(
      tester,
      width: 320,
      height: 1400,
      locale: const Locale('ar'),
      path: '/settings/chat',
    );
    expect(tester.takeException(), isNull);
    final row = find.byKey(const ValueKey('settings_folders'));
    expect(row, findsOneWidget);
    final icon = tester.getCenter(
      find.descendant(of: row, matching: find.byType(Icon)).first,
    );
    expect(icon.dx, greaterThan(160), reason: 'the icon tile is on the right');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_chat_rtl.png'),
    );
    await harness.finish(tester);
  });
}
