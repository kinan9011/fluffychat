// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_config.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/settings_appearance/settings_appearance.dart';
import 'package:odango/utils/oklch.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
  });

  group('accent swatches (m5)', () {
    test('a grey system colour is not offered', () {
      final swatches = SettingsAppearanceController.accentSwatches(
        const Color(0xFF808080),
      );
      expect(swatches, isNot(contains(const Color(0xFF808080))));
      expect(swatches.every((c) => accentHueOf(c) != null), isTrue);
    });

    test('without a system colour the list starts with the app colour', () {
      expect(
        SettingsAppearanceController.accentSwatches(null).first,
        AppConfig.chatColor,
      );
    });

    test('a coloured system colour comes first', () {
      const system = Color(0xFF2E7D32);
      expect(SettingsAppearanceController.accentSwatches(system).first, system);
    });

    test('exactly one swatch is checked even when two share the hue', () {
      final swatches = [
        AppConfig.chatColor,
        AppConfig.chatColor,
        const Color(0xFF2E7D32),
      ];
      final hue = accentHueOf(AppConfig.chatColor)!.toInt();
      expect(SettingsAppearanceController.checkedSwatch(swatches, hue), 0);
    });

    test('no swatch is checked for an unknown hue', () {
      expect(
        SettingsAppearanceController.checkedSwatch([AppConfig.chatColor], 1),
        isNull,
      );
    });
  });

  testWidgets('Appearance has a Reduce transparency switch', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await AppSettings.reduceTransparency.setItem(false);
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    FluffyChatApp.router.go('/settings/appearance');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    final tile = find.text('Reduce transparency');
    expect(tile, findsOneWidget);
    expect(
      find.text('Use solid backgrounds instead of blurred glass'),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pump();
    expect(AppSettings.reduceTransparency.value, isTrue);
    await tester.pump(const Duration(seconds: 35));
  });
}
