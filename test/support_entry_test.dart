// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/pages/support/support_dialog.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets('the support entry of the overflow menu opens the dialog', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms');
    await harness.settle(tester);

    await tester.tap(find.byKey(const Key('accounts_and_settings_buttons')));
    await harness.settle(tester);
    expect(find.text('Support Odango'), findsOneWidget);

    await tester.tap(find.text('Support Odango'));
    await harness.settle(tester);
    expect(find.byType(SupportDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await harness.settle(tester);
    expect(find.byType(SupportDialog), findsNothing);
    await harness.finish(tester);
  });
}
