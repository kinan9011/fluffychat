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

Future<ThemeData> build(WidgetTester tester, Brightness brightness) async {
  late ThemeData theme;
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Builder(
        builder: (context) {
          theme = FluffyThemes.buildTheme(context, brightness);
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

  testWidgets('text on the error colour is >= 4.5:1 in both themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final scheme = (await build(tester, brightness)).colorScheme;
      expect(
        wcagContrast(scheme.onError, scheme.error),
        greaterThanOrEqualTo(4.5),
        reason: brightness.name,
      );
      expect(
        scheme.onError,
        brightness == Brightness.dark
            ? AppTokens.dark().onRed
            : AppTokens.light().onRed,
      );
    }
  });

  group('accentHueOf', () {
    test('rounds a swatch to the exact hue and ignores greys', () {
      expect(accentHueOf(AppConfig.chatColor), 268);
      expect(accentHueOf(const Color(0xFF5625BA)), 289);
      expect(accentHueOf(const Color(0xFFF44336)), 29);
      expect(accentHueOf(const Color(0xFF4CAF50)), 144);
      expect(accentHueOf(const Color(0xFF9E9E9E)), isNull);
    });
  });

  group('single accent source (B1)', () {
    testWidgets('an explicit user 268 beats a deployer seed', (tester) async {
      AppSettings.applyPlatformConfiguration({
        'colorSchemeSeedInt': 0xFF4CAF50,
      }, PlatformConfigSource.web);
      await AppSettings.accentHue.setItem(268);
      expect(FluffyThemes.accentHue(), 268);
      final theme = await build(tester, Brightness.light);
      expect(theme.extension<AppTokens>(), AppTokens.light());
    });

    testWidgets('a deployer seed 0xFF5625BA is honoured', (tester) async {
      AppSettings.applyPlatformConfiguration({
        'colorSchemeSeedInt': 0xFF5625BA,
      }, PlatformConfigSource.web);
      expect(FluffyThemes.accentHue(), 289);
      final theme = await build(tester, Brightness.light);
      expect(theme.extension<AppTokens>(), AppTokens.light(hue: 289));
    });

    testWidgets('a deployer accentHue wins over a deployer seed', (
      tester,
    ) async {
      AppSettings.applyPlatformConfiguration({
        'colorSchemeSeedInt': 0xFF4CAF50,
        'accentHue': 330,
      }, PlatformConfigSource.web);
      expect(FluffyThemes.accentHue(), 330);
      final theme = await build(tester, Brightness.dark);
      expect(theme.extension<AppTokens>(), AppTokens.dark(hue: 330));
    });

    testWidgets('a user hue wins over a deployer accentHue', (tester) async {
      AppSettings.applyPlatformConfiguration({
        'accentHue': 330,
      }, PlatformConfigSource.web);
      await AppSettings.accentHue.setItem(155);
      expect(FluffyThemes.accentHue(), 155);
    });

    testWidgets('a grey deployer seed has no hue and the default applies', (
      tester,
    ) async {
      AppSettings.applyPlatformConfiguration({
        'colorSchemeSeedInt': 0xFF9E9E9E,
      }, PlatformConfigSource.web);
      expect(FluffyThemes.accentHue(), 268);
    });

    testWidgets('nothing configured gives hue 268', (tester) async {
      expect(FluffyThemes.accentHue(), 268);
      final theme = await build(tester, Brightness.light);
      expect(theme.extension<AppTokens>(), AppTokens.light());
    });

    testWidgets('an out-of-range user hue is normalised', (tester) async {
      await AppSettings.accentHue.setItem(-30);
      expect(FluffyThemes.accentHue(), 330);
    });
  });

  group('legacy accent migration', () {
    Future<SharedPreferences> prefs(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('primary_color is migrated once to accentHue', () async {
      final store = await prefs({'primary_color': 0xFFF44336});
      await AppSettings.migrateLegacyAccent(store);
      expect(store.getInt(AppSettings.accentHue.key), 29);
      expect(store.containsKey('primary_color'), isFalse);
      await AppSettings.migrateLegacyAccent(store);
      expect(store.getInt(AppSettings.accentHue.key), 29);
    });

    test('an existing accentHue is kept, the legacy key is removed', () async {
      final store = await prefs({
        'primary_color': 0xFFF44336,
        AppSettings.accentHue.key: 155,
      });
      await AppSettings.migrateLegacyAccent(store);
      expect(store.getInt(AppSettings.accentHue.key), 155);
      expect(store.containsKey('primary_color'), isFalse);
    });

    test('a grey legacy colour writes no hue', () async {
      final store = await prefs({'primary_color': 0xFF9E9E9E});
      await AppSettings.migrateLegacyAccent(store);
      expect(store.containsKey(AppSettings.accentHue.key), isFalse);
      expect(store.containsKey('primary_color'), isFalse);
    });

    test('a stored user colorSchemeSeedInt is migrated and removed', () async {
      final store = await prefs({
        AppSettings.colorSchemeSeedInt.key: 0xFF5625BA,
      });
      await AppSettings.migrateLegacyAccent(store);
      expect(store.getInt(AppSettings.accentHue.key), 289);
      expect(store.containsKey(AppSettings.colorSchemeSeedInt.key), isFalse);
    });

    test('primary_color wins over a stored colorSchemeSeedInt', () async {
      final store = await prefs({
        'primary_color': 0xFFF44336,
        AppSettings.colorSchemeSeedInt.key: 0xFF4CAF50,
      });
      await AppSettings.migrateLegacyAccent(store);
      expect(store.getInt(AppSettings.accentHue.key), 29);
      expect(store.containsKey(AppSettings.colorSchemeSeedInt.key), isFalse);
    });

    test('a wrongly typed legacy value is removed without a crash', () async {
      final store = await prefs({'primary_color': 'oops'});
      await AppSettings.migrateLegacyAccent(store);
      expect(store.containsKey('primary_color'), isFalse);
      expect(store.containsKey(AppSettings.accentHue.key), isFalse);
    });

    test('nothing stored is a no-op', () async {
      final store = await prefs({});
      await AppSettings.migrateLegacyAccent(store);
      expect(store.getKeys(), isEmpty);
    });
  });
}
