// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpGlass(
  WidgetTester tester, {
  double blur = 20,
  List<BoxShadow>? shadows,
  BorderRadius radius = const BorderRadius.all(Radius.circular(20)),
  bool highContrast = false,
  bool solid = false,
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
}) {
  final tokens = brightness == Brightness.dark
      ? AppTokens.dark()
      : AppTokens.light();
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Directionality(
        textDirection: direction,
        child: Theme(
          data: ThemeData(brightness: brightness, extensions: [tokens]),
          child: GlassSurface(
            solid: solid,
            blur: blur,
            shadows: shadows,
            borderRadius: radius,
            child: const Text('hello'),
          ),
        ),
      ),
    ),
  );
}

Color surfaceColor(WidgetTester tester) {
  final decorated = tester.widget<DecoratedBox>(
    find.byKey(GlassSurface.surfaceKey),
  );
  return (decorated.decoration as BoxDecoration).color!;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.reduceTransparency.setItem(false);
  });

  testWidgets(
    'default mode blurs the backdrop with the translucent glass token',
    (tester) async {
      await pumpGlass(tester);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(surfaceColor(tester), AppTokens.light().glass);
      expect(find.text('hello'), findsOneWidget);
    },
  );

  testWidgets('high contrast OS setting falls back to solid surf, no blur', (
    tester,
  ) async {
    await pumpGlass(tester, highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(surfaceColor(tester), AppTokens.light().surf);
    expect(surfaceColor(tester).a, 1);
  });

  testWidgets('reduceTransparency setting falls back to solid surf, no blur', (
    tester,
  ) async {
    await AppSettings.reduceTransparency.setItem(true);
    await pumpGlass(tester, brightness: Brightness.dark);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(surfaceColor(tester), AppTokens.dark().surf);
  });

  testWidgets('solid parameter forces the fallback', (tester) async {
    await pumpGlass(tester, solid: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(surfaceColor(tester), AppTokens.light().surf);
  });

  testWidgets('hairline border and content render in RTL too', (tester) async {
    await pumpGlass(tester, direction: TextDirection.rtl);
    final decoration =
        tester
                .widget<DecoratedBox>(find.byKey(GlassSurface.surfaceKey))
                .decoration
            as BoxDecoration;
    expect((decoration.border! as Border).top.color, AppTokens.light().glassBd);
    expect(find.text('hello'), findsOneWidget);
  });

  group('glass recipe', () {
    List<double> apply(List<double> m, List<double> rgb) => [
      for (var row = 0; row < 3; row++)
        m[row * 5] * rgb[0] + m[row * 5 + 1] * rgb[1] + m[row * 5 + 2] * rgb[2],
    ];

    test('saturate matrix keeps neutrals neutral and preserves luminance', () {
      const m = GlassSurface.saturateMatrix;
      for (var row = 0; row < 3; row++) {
        expect(
          m[row * 5] + m[row * 5 + 1] + m[row * 5 + 2],
          closeTo(1, 1e-9),
          reason: 'row $row',
        );
      }
      for (final grey in [0.0, 0.25, 0.5, 1.0]) {
        final out = apply(m, [grey, grey, grey]);
        for (final channel in out) {
          expect(channel, closeTo(grey, 1e-9));
        }
      }
      double luma(List<double> c) => 0.213 * c[0] + 0.715 * c[1] + 0.072 * c[2];
      for (final rgb in [
        [0.9, 0.2, 0.1],
        [0.2, 0.7, 0.4],
        [0.3, 0.3, 0.8],
      ]) {
        expect(luma(apply(m, rgb)), closeTo(luma(rgb), 0.002));
      }
    });

    test('saturate matrix really saturates by 1.4', () {
      final out = apply(GlassSurface.saturateMatrix, [0.8, 0.4, 0.4]);
      const lum = 0.213 * 0.8 + 0.715 * 0.4 + 0.072 * 0.4;
      expect(out[0], closeTo(lum + 1.4 * (0.8 - lum), 0.002));
      expect(out[1], closeTo(lum + 1.4 * (0.4 - lum), 0.002));
    });

    testWidgets(
      'backdrop filter is blur(20) composed with the saturate matrix',
      (tester) async {
        await pumpGlass(tester);
        final filter = tester
            .widget<BackdropFilter>(find.byType(BackdropFilter))
            .filter;
        expect(
          filter,
          ImageFilter.compose(
            outer: const ColorFilter.matrix(GlassSurface.saturateMatrix),
            inner: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          ),
        );
      },
    );

    testWidgets('blur is forwarded (menus use 24)', (tester) async {
      await pumpGlass(tester, blur: 24);
      final filter = tester
          .widget<BackdropFilter>(find.byType(BackdropFilter))
          .filter;
      expect(
        filter,
        ImageFilter.compose(
          outer: const ColorFilter.matrix(GlassSurface.saturateMatrix),
          inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        ),
      );
    });

    testWidgets('radius is applied to the clip', (tester) async {
      await pumpGlass(tester, radius: BorderRadius.circular(24));
      expect(
        tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
        BorderRadius.circular(24),
      );
    });

    testWidgets('shadow defaults to AppElevation.glass and can be replaced', (
      tester,
    ) async {
      List<BoxShadow> shadowOf() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.boxShadow)
          .whereType<List<BoxShadow>>()
          .single;
      await pumpGlass(tester);
      expect(shadowOf(), AppElevation.glass(AppTokens.light().shadow));
      await pumpGlass(tester, shadows: AppElevation.menu);
      expect(shadowOf(), AppElevation.menu);
    });

    testWidgets('shadow is clipped out of the glass interior', (tester) async {
      await pumpGlass(tester);
      final clipper = tester.widget<ClipPath>(find.byType(ClipPath)).clipper!;
      final path = clipper.getClip(const Size(200, 100));
      expect(path.contains(const Offset(100, 50)), isFalse);
      expect(path.contains(const Offset(100, 105)), isTrue);
      expect(path.contains(const Offset(-6, 50)), isTrue);
    });
  });
}
