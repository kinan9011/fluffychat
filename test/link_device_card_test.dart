// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/device_settings/link_device_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, VoidCallback? onOpen) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.light()]),
        home: Scaffold(body: LinkDeviceCard(onOpenAccountPage: onOpen)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without an account page it does not point to one', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.textContaining("can't scan one yet"), findsOneWidget);
    expect(find.textContaining('account page'), findsNothing);
    expect(
      find.byKey(const ValueKey('link_device_open_account')),
      findsNothing,
    );
  });

  testWidgets('with an account page it says what the page is for', (
    tester,
  ) async {
    var opened = 0;
    await pump(tester, () => opened++);
    expect(find.textContaining('account page lists'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link_device_open_account')));
    expect(opened, 1);
  });
}
