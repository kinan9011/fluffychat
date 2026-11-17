// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/crypto_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';

/// The Arabic delegate loads asynchronously and only the first test of a file
/// gets it reliably (m10), so every RTL golden of the settings lives in this
/// one test.
void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    loadCryptoIdentityConnected = (_) async => true;
  });
  tearDown(() async {
    loadCryptoIdentityConnected = defaultLoadCryptoIdentityConnected;
    await harness.tearDown();
  });

  testWidgets('settings pages mirror in RTL', (tester) async {
    await harness.open(tester, path: '/settings', locale: const Locale('ar'));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_root_rtl.png'),
    );
    await harness.finish(tester);

    await harness.open(
      tester,
      path: '/rooms/${harness.room.id}/appearance',
      locale: const Locale('ar'),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_appearance_chat_rtl.png'),
    );
    await harness.finish(tester);

    await harness.open(
      tester,
      path: '/settings/security',
      locale: const Locale('ar'),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_privacy_rtl.png'),
    );
    await harness.finish(tester);

    await harness.open(tester, path: '/settings', locale: const Locale('ar'));
    await tester.tap(find.byKey(const ValueKey('settings_set_status')));
    await harness.settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/status_sheet_rtl.png'),
    );
    await harness.finish(tester);

    await harness.open(
      tester,
      path: '/settings/data/export?room=${harness.room.id}',
      locale: const Locale('ar'),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/export_page_rtl.png'),
    );
    await harness.finish(tester);

    await harness.open(
      tester,
      path: '/settings/data',
      locale: const Locale('ar'),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_data_rtl.png'),
    );
    await harness.finish(tester);
  });
}
