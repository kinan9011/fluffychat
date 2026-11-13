// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeData> build(
  WidgetTester tester,
  Brightness brightness, [
  Color? seed,
]) async {
  late ThemeData theme;
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Builder(
        builder: (context) {
          theme = FluffyThemes.buildTheme(context, brightness, seed);
          return const SizedBox();
        },
      ),
    ),
  );
  return theme;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.remove(AppSettings.accentHue.key);
    await AppSettings.store.remove(AppSettings.colorSchemeSeedInt.key);
  });

  tearDown(
    () =>
        AppSettings.applyPlatformConfiguration(null, PlatformConfigSource.web),
  );

  for (final brightness in Brightness.values) {
    final tokens = brightness == Brightness.dark
        ? AppTokens.dark()
        : AppTokens.light();

    testWidgets(
      '${brightness.name}: default look is hue 268 and the ColorScheme follows the tokens',
      (tester) async {
        final theme = await build(tester, brightness);
        expect(theme.extension<AppTokens>(), tokens);
        final scheme = theme.colorScheme;
        expect(scheme.brightness, brightness);
        expect(scheme.primary, tokens.acc);
        expect(scheme.onPrimary, tokens.onacc);
        expect(scheme.primaryContainer, tokens.accs);
        expect(scheme.surface, tokens.surf);
        expect(scheme.onSurface, tokens.fg);
        expect(scheme.onSurfaceVariant, tokens.mut);
        expect(scheme.error, tokens.red);
        expect(theme.scaffoldBackgroundColor, tokens.bg);
        expect(theme.dividerColor, tokens.line);
      },
    );

    testWidgets(
      '${brightness.name}: text theme uses Figtree, the DESIGN type scale and fg',
      (tester) async {
        final text = (await build(tester, brightness)).textTheme;
        expect(text.bodyLarge!.fontFamily, 'Figtree');
        expect(text.bodyLarge!.fontSize, 15.5);
        expect(text.bodyLarge!.height, 1.35);
        expect(text.bodyLarge!.color, tokens.fg);
        expect(text.titleLarge!.fontSize, 22);
        expect(text.titleLarge!.fontWeight, FontWeight.w700);
        expect(text.headlineMedium!.fontSize, 26);
        expect(text.titleMedium!.fontWeight, FontWeight.w600);
        expect(text.labelMedium!.color, tokens.fg);
      },
    );
  }

  testWidgets('accent hue setting changes the accent, not the neutrals', (
    tester,
  ) async {
    await AppSettings.accentHue.setItem(155);
    final theme = await build(tester, Brightness.light);
    expect(theme.extension<AppTokens>(), AppTokens.light(hue: 155));
    expect(theme.colorScheme.surface, AppTokens.light().surf);
  });

  testWidgets('a custom colour keeps working: its hue replaces the setting', (
    tester,
  ) async {
    final seed = oklchColor(0.5, 0.15, 25);
    final theme = await build(tester, Brightness.light, seed);
    final hue = oklchOf(theme.colorScheme.primary).h;
    expect(hue, closeTo(25, 3));
  });

  testWidgets('a grey seed has no hue and falls back to the setting', (
    tester,
  ) async {
    final theme = await build(
      tester,
      Brightness.light,
      const Color(0xFF808080),
    );
    expect(theme.extension<AppTokens>(), AppTokens.light());
  });

  testWidgets('the default swatch maps back to exactly hue 268', (
    tester,
  ) async {
    final theme = await build(tester, Brightness.light, AppConfig.chatColor);
    expect(theme.extension<AppTokens>(), AppTokens.light());
  });

  group('deployer config (web config.json / MDM)', () {
    final legacySeed = oklchColor(0.5, 0.15, 155);

    testWidgets('colorSchemeSeedInt still sets the accent hue', (tester) async {
      await AppSettings.colorSchemeSeedInt.setItem(legacySeed.toARGB32());
      final theme = await build(tester, Brightness.light);
      expect(theme.extension<AppTokens>(), AppTokens.light(hue: 155));
    });

    testWidgets('the default colorSchemeSeedInt value is ignored', (
      tester,
    ) async {
      await AppSettings.colorSchemeSeedInt.setItem(
        AppSettings.colorSchemeSeedInt.defaultValue,
      );
      final theme = await build(tester, Brightness.light);
      expect(theme.extension<AppTokens>(), AppTokens.light());
    });

    testWidgets('accentHue wins over the legacy seed', (tester) async {
      await AppSettings.colorSchemeSeedInt.setItem(legacySeed.toARGB32());
      await AppSettings.accentHue.setItem(330);
      final theme = await build(tester, Brightness.dark);
      expect(theme.extension<AppTokens>(), AppTokens.dark(hue: 330));
    });

    testWidgets('a colour the user picked wins over deployer config', (
      tester,
    ) async {
      await AppSettings.accentHue.setItem(330);
      final theme = await build(
        tester,
        Brightness.light,
        oklchColor(0.5, 0.15, 25),
      );
      expect(oklchOf(theme.colorScheme.primary).h, closeTo(25, 3));
    });

    testWidgets('a deployer config.json value is applied end to end', (
      tester,
    ) async {
      AppSettings.applyPlatformConfiguration({
        'colorSchemeSeedInt': legacySeed.toARGB32(),
      }, PlatformConfigSource.web);
      final theme = await build(tester, Brightness.light);
      expect(theme.extension<AppTokens>(), AppTokens.light(hue: 155));
    });
  });
}
