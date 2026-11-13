// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';

const goldenSeedColor = Color(0xFF5625BA);

/// Light, dark and one RTL variant. Every new component gets these.
const goldenVariants = <({String suffix, Brightness brightness, bool rtl})>[
  (suffix: 'light', brightness: Brightness.light, rtl: false),
  (suffix: 'dark', brightness: Brightness.dark, rtl: false),
  (suffix: 'rtl', brightness: Brightness.light, rtl: true),
];

/// Pumps [child] inside the app theme and localizations, without needing
/// network, shared preferences or a Matrix client.
Future<void> pumpGoldenWidget(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  bool rtl = false,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 300),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    Builder(
      builder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: FluffyThemes.buildTheme(context, brightness, goldenSeedColor),
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
      size: size,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/${name}_${variant.suffix}.png'),
    );
  }
}
