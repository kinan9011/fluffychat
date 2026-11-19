// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/utils/oklch.dart';

/// DESIGN.md 13 for the conversation: text pairs 4.5:1, graphics 3:1, for
/// every accent hue in both themes.
void main() {
  const white = Color(0xFFFFFFFF);
  const black = Color(0xFF000000);

  Map<String, AppTokens> themes(double hue) => {
    'light': AppTokens.light(hue: hue),
    'dark': AppTokens.dark(hue: hue),
  };

  void expectAll(
    String name,
    double minimum,
    ({double ratio, String where}) Function(AppTokens t) measure,
  ) {
    test(name, () {
      final failures = <String>[];
      for (var hue = 0; hue < 360; hue++) {
        for (final entry in themes(hue.toDouble()).entries) {
          final m = measure(entry.value);
          if (m.ratio < minimum) {
            failures.add(
              '${entry.key} hue $hue ${m.where}: ${m.ratio.toStringAsFixed(2)}',
            );
          }
        }
      }
      expect(failures, isEmpty);
    });
  }

  ({double ratio, String where}) pair(Color fg, Color bg, String where) =>
      (ratio: wcagContrast8(fg, bg), where: where);

  expectAll('text on the incoming bubble', 4.5, (t) {
    final worst = [
      wcagContrast8(t.fg, t.surf),
      wcagContrast8(t.mut, t.surf),
      wcagContrast8(t.acc, t.surf),
    ].reduce((a, b) => a < b ? a : b);
    return (ratio: worst, where: 'fg, mut, acc on surf');
  });

  expectAll('white on the outgoing bubble and its time and ticks', 4.5, (t) {
    final worst = [
      wcagContrast8(t.outFg, t.outS),
      wcagContrast8(t.outMut, t.outS),
    ].reduce((a, b) => a < b ? a : b);
    return (ratio: worst, where: 'outFg, outMut on outS');
  });

  expectAll('text on the edit history diff colours', 4.5, (t) {
    final removed = Color.alphaBlend(t.red.withValues(alpha: .22), t.surf2);
    final added = Color.alphaBlend(t.ok.withValues(alpha: .25), t.surf2);
    final worst = [
      wcagContrast8(t.fg, removed),
      wcagContrast8(t.fg, added),
    ].reduce((a, b) => a < b ? a : b);
    return (ratio: worst, where: 'fg on removed and added tint');
  });

  Color deleteFill(AppTokens t) =>
      Color.alphaBlend(t.red.withValues(alpha: .14), t.surf);

  expectAll(
    'the delete action label on its red tint',
    4.5,
    (t) => pair(t.fg, deleteFill(t), 'fg on red 14% over surf'),
  );

  expectAll(
    'the delete action icon on its red tint',
    3,
    (t) => pair(t.red, deleteFill(t), 'red icon on red 14% over surf'),
  );

  expectAll(
    'text on the accent button',
    4.5,
    (t) => pair(t.onacc, t.acc, 'onacc on acc'),
  );

  expectAll(
    'text on a failed bubble',
    4.5,
    (t) => pair(t.onRed, t.red, 'onRed on red'),
  );

  expectAll('the amber ring and the accent ring are visible on the bubble', 3, (
    t,
  ) {
    final worst = [
      wcagContrast8(t.warn, t.surf),
      wcagContrast8(t.acc, t.surf),
    ].reduce((a, b) => a < b ? a : b);
    return (ratio: worst, where: 'warn, acc on surf');
  });

  expectAll(
    'the primary text stays readable on glass over the worst backdrop',
    4.5,
    (t) {
      final worst = [
        for (final backdrop in [white, black])
          wcagContrast8(t.fg, Color.alphaBlend(t.glass, backdrop)),
      ].reduce((a, b) => a < b ? a : b);
      return (ratio: worst, where: 'fg on glass over white and black');
    },
  );

  test('secondary text on glass is only safe on its own theme backdrop', () {
    final light = AppTokens.light();
    final dark = AppTokens.dark();
    final lightOnWhite = wcagContrast8(
      light.mut,
      Color.alphaBlend(light.glass, white),
    );
    final darkOnBlack = wcagContrast8(
      dark.mut,
      Color.alphaBlend(dark.glass, black),
    );
    expect(lightOnWhite, greaterThanOrEqualTo(4.5));
    expect(darkOnBlack, greaterThanOrEqualTo(4.5));
  });
}
