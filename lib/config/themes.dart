// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

enum ShellMode {
  mobile,
  twoPane,
  rail,
  wide;

  static ShellMode forWidth(double width) {
    if (width >= FluffyThemes.threePaneBreakpoint) return wide;
    if (width >= FluffyThemes.railBreakpoint) return rail;
    if (width >= FluffyThemes.twoPaneBreakpoint) return twoPane;
    return mobile;
  }

  bool get hasRail => this == rail || this == wide;
}

abstract class FluffyThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 76.0;
  static const double listColumnWidth = 350.0;
  static const double detailsPanelWidth = 340.0;

  static const double twoPaneBreakpoint = 600.0;
  static const double railBreakpoint = 900.0;
  static const double threePaneBreakpoint = 1280.0;

  static bool isColumnModeByWidth(double width) => width >= twoPaneBreakpoint;

  static bool isThreeColumnModeByWidth(double width) =>
      width >= threePaneBreakpoint;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      isThreeColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Curve animationCurve = Curves.easeInOut;

  /// Precedence: the user's `accentHue` (a stored key is the user's intent,
  /// even if it equals the default), then deployer `accentHue`, then deployer
  /// `colorSchemeSeedInt` (web config.json, MDM), then hue 268.
  static double accentHue() {
    if (AppSettings.store.containsKey(AppSettings.accentHue.key) ||
        AppSettings.accentHue.hasPlatformValue) {
      return normalizeHue(AppSettings.accentHue.value.toDouble());
    }
    if (!AppSettings.colorSchemeSeedInt.hasPlatformValue) {
      return defaultAccentHue;
    }
    return accentHueOf(Color(AppSettings.colorSchemeSeedInt.value)) ??
        defaultAccentHue;
  }

  static ThemeData buildTheme(BuildContext context, Brightness brightness) {
    final hue = accentHue();
    final isDark = brightness == Brightness.dark;
    final tokens = isDark
        ? AppTokens.dark(hue: hue)
        : AppTokens.light(hue: hue);
    final colorScheme =
        ColorScheme.fromSeed(
          brightness: brightness,
          seedColor: tokens.acc,
          dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
        ).copyWith(
          primary: tokens.acc,
          onPrimary: tokens.onacc,
          primaryContainer: tokens.accs,
          onPrimaryContainer: tokens.fg,
          surface: tokens.surf,
          onSurface: tokens.fg,
          onSurfaceVariant: tokens.mut,
          outline: tokens.mut,
          outlineVariant: tokens.line,
          error: tokens.red,
          onError: tokens.onRed,
          surfaceContainerLowest: tokens.bg,
          surfaceContainerLow: tokens.surf,
          surfaceContainer: tokens.surf2,
          surfaceContainerHigh: tokens.surf,
          surfaceContainerHighest: tokens.line,
        );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [tokens],
      fontFamily: _fontFamily,
      textTheme: _textTheme(brightness, tokens),
      scaffoldBackgroundColor: tokens.bg,
      dividerColor: tokens.line,
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(AppSpacing.l),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        surfaceTintColor: isColumnMode ? colorScheme.surface : null,
        backgroundColor: isColumnMode ? colorScheme.surface : null,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: isColumnMode
          ? const SnackBarThemeData(
              showCloseIcon: true,
              behavior: SnackBarBehavior.floating,
              width: FluffyThemes.columnWidth * 1.5,
            )
          : const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 0,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

const _fontFamily = 'Figtree';

TextTheme _textTheme(Brightness brightness, AppTokens tokens) {
  final base =
      (brightness == Brightness.dark
              ? Typography.material2021().white
              : Typography.material2021().black)
          .apply(
            fontFamily: _fontFamily,
            bodyColor: tokens.fg,
            displayColor: tokens.fg,
          );
  return base.copyWith(
    headlineMedium: base.headlineMedium!.copyWith(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.52,
    ),
    headlineSmall: base.headlineSmall!.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: base.titleLarge!.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: base.titleMedium!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.bodyLarge!.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.35,
    ),
    bodyMedium: base.bodyMedium!.copyWith(
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: base.bodySmall!.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: base.labelLarge!.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.labelMedium!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.48,
    ),
    labelSmall: base.labelSmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
  );
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

extension BubbleColorTheme on ThemeData {
  Color get bubbleColor => brightness == Brightness.light
      ? colorScheme.primary
      : colorScheme.primaryContainer;

  Color get onBubbleColor => brightness == Brightness.light
      ? colorScheme.onPrimary
      : colorScheme.onPrimaryContainer;

  Color get secondaryBubbleColor => HSLColor.fromColor(
    brightness == Brightness.light
        ? colorScheme.tertiary
        : colorScheme.tertiaryContainer,
  ).withSaturation(0.5).toColor();
}
