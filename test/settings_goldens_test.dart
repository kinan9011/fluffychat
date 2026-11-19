// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/crypto_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';

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

  Future<void> golden(
    WidgetTester tester,
    String name,
    String path,
    Brightness brightness,
    String suffix,
  ) async {
    await harness.open(tester, path: path, brightness: brightness);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/${name}_$suffix.png'),
    );
    await harness.finish(tester);
  }

  for (final (brightness, suffix) in [
    (Brightness.light, 'light'),
    (Brightness.dark, 'dark'),
  ]) {
    testWidgets('settings root $suffix', (tester) async {
      await golden(tester, 'settings_root', '/settings', brightness, suffix);
    });

    testWidgets('chat settings $suffix', (tester) async {
      await harness.open(
        tester,
        path: '/settings/chat',
        brightness: brightness,
        height: 1500,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_chat_$suffix.png'),
      );
      await harness.finish(tester);
    });

    testWidgets('privacy and security $suffix', (tester) async {
      await golden(
        tester,
        'settings_privacy',
        '/settings/security',
        brightness,
        suffix,
      );
    });

    testWidgets('export chat $suffix', (tester) async {
      await golden(
        tester,
        'export_page',
        '/settings/data/export?room=${harness.room.id}',
        brightness,
        suffix,
      );
    });

    testWidgets('data and storage $suffix', (tester) async {
      await golden(
        tester,
        'settings_data',
        '/settings/data',
        brightness,
        suffix,
      );
    });

    testWidgets('status sheet $suffix', (tester) async {
      await harness.open(tester, path: '/settings', brightness: brightness);
      await tester.tap(find.byKey(const ValueKey('settings_set_status')));
      await harness.settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/status_sheet_$suffix.png'),
      );
      await harness.finish(tester);
    });

    testWidgets('appearance (all chats) $suffix', (tester) async {
      await golden(
        tester,
        'settings_appearance',
        '/settings/appearance',
        brightness,
        suffix,
      );
    });

    testWidgets('appearance (one chat) $suffix', (tester) async {
      await golden(
        tester,
        'settings_appearance_chat',
        '/rooms/${harness.room.id}/appearance',
        brightness,
        suffix,
      );
    });
  }
}
