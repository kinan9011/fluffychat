// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark and one RTL variant (Arabic locale). Every new component gets
/// these. The test font set has no Arabic glyphs, so Arabic text renders as
/// boxes: layout direction and l10n strings are covered, glyph shapes are not.
const goldenVariants =
    <({String suffix, Brightness brightness, bool rtl, Locale locale})>[
      (
        suffix: 'light',
        brightness: Brightness.light,
        rtl: false,
        locale: Locale('en'),
      ),
      (
        suffix: 'dark',
        brightness: Brightness.dark,
        rtl: false,
        locale: Locale('en'),
      ),
      (
        suffix: 'rtl',
        brightness: Brightness.light,
        rtl: true,
        locale: Locale('ar'),
      ),
    ];

/// Pumps [child] inside the app theme (default accent hue) and localizations,
/// without needing network or a Matrix client.
Future<void> pumpGoldenWidget(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  bool rtl = false,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 300),
}) async {
  SharedPreferences.setMockInitialValues({});
  await AppSettings.init(loadWebConfigFile: false);
  await AppSettings.store.remove(AppSettings.accentHue.key);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    Builder(
      builder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: FluffyThemes.buildTheme(context, brightness),
        localizationsDelegates: [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        builder: (context, app) => Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: app!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.loadAssets();
  await tester.pump();
}

/// Compares [child] against `test/goldens/<name>_<variant>.png` for every
/// entry of [goldenVariants]. Update with `flutter test --update-goldens`.
Future<void> expectGoldenVariants(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = const Size(400, 300),
}) async {
  for (final variant in goldenVariants) {
    await pumpGoldenWidget(
      tester,
      child,
      brightness: variant.brightness,
      rtl: variant.rtl,
      locale: variant.locale,
      size: size,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/${name}_${variant.suffix}.png'),
    );
  }
}
