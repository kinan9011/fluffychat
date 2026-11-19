// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/account_hooks.dart';

import 'utils/chat_page_harness.dart';
import 'utils/test_client.dart';

/// W03 I1: the notice that a device is not verified belongs to the account
/// that was hooked. When the user switched to another account while the first
/// sync of the first one was still running, it must not show up over the
/// other account.
void main() {
  final harness = ChatPageHarness();
  late Client other;

  setUpAll(() async {
    await harness.setUpAll();
    other = await prepareTestClient(clientName: 'Other account');
  });
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> run(WidgetTester tester, Client client) async {
    final context = tester.element(find.byType(Scaffold).first);
    await tester.runAsync(
      () => showUnverifiedDeviceNoticeAfterFirstSync(client, context),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the active account gets the notice', (tester) async {
    await harness.open(tester, path: '/settings');
    await run(tester, harness.client);
    final l10n = L10n.of(tester.element(find.byType(Scaffold).first));
    expect(find.text(l10n.oneOfYourDevicesIsNotVerified), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('another account that is not the active one does not', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings');
    await run(tester, other);
    final l10n = L10n.of(tester.element(find.byType(Scaffold).first));
    expect(find.text(l10n.oneOfYourDevicesIsNotVerified), findsNothing);
    await harness.finish(tester);
  });
}
