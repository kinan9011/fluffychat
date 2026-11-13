// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/oklch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

int _channel(double value) => (value * 255).round();

void expectRgb(Color color, int r, int g, int b, {int tolerance = 1}) {
  expect(_channel(color.r), closeTo(r, tolerance), reason: 'r of $color');
  expect(_channel(color.g), closeTo(g, tolerance), reason: 'g of $color');
  expect(_channel(color.b), closeTo(b, tolerance), reason: 'b of $color');
}

void main() {
  group('oklchColor reference values', () {
    test('white and black', () {
      expectRgb(oklchColor(1, 0, 0), 255, 255, 255, tolerance: 0);
      expectRgb(oklchColor(0, 0, 0), 0, 0, 0, tolerance: 0);
    });

    test('mid grey is neutral', () {
      // oklch(0.5 0 0) is #636363 in CSS Color 4.
      expectRgb(oklchColor(0.5, 0, 123), 99, 99, 99);
    });

    test('sRGB primaries from the CSS Color 4 spec', () {
      expectRgb(oklchColor(0.62796, 0.25768, 29.234), 255, 0, 0);
      expectRgb(oklchColor(0.86644, 0.29483, 142.495), 0, 255, 0);
      expectRgb(oklchColor(0.45201, 0.31321, 264.052), 0, 0, 255);
    });

    test('DESIGN accent oklch(0.53 0.16 268) is #4463C7', () {
      expectRgb(oklchColor(0.53, 0.16, 268), 0x44, 0x63, 0xC7);
    });

    test('alpha is passed through', () {
      expect(oklchColor(0.5, 0.1, 10, 0.5).a, closeTo(0.5, 0.001));
    });

    test('hue wraps around 360 and negative hues', () {
      final base = oklchColor(0.6, 0.1, 40);
      expect(oklchColor(0.6, 0.1, 400), base);
      expect(oklchColor(0.6, 0.1, -320), base);
    });
  });

  group('gamut mapping', () {
    test('out-of-gamut chroma is reduced, hue and lightness are kept', () {
      final color = oklchColor(0.9, 0.4, 142);
      expect(color.a, 1);
      expect(color.r, inInclusiveRange(0, 1));
      expect(color.g, inInclusiveRange(0, 1));
      expect(color.b, inInclusiveRange(0, 1));
      final back = oklchOf(color);
      expect(back.l, closeTo(0.9, 0.02));
      expect(back.h, closeTo(142, 3));
      expect(back.c, lessThan(0.4));
    });

    test('lightness outside 0..1 clamps to black and white', () {
      expectRgb(oklchColor(1.4, 0.2, 10), 255, 255, 255, tolerance: 0);
      expectRgb(oklchColor(-0.2, 0.2, 10), 0, 0, 0, tolerance: 0);
    });

    test('NaN and infinite input never throws and stays a valid colour', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final color = oklchColor(value, value, value, value);
        expect(color.r.isNaN, isFalse);
        expect(color.g.isNaN, isFalse);
        expect(color.b.isNaN, isFalse);
        expect(color.a.isNaN, isFalse);
      }
    });
  });

  group('oklchOf', () {
    test('round trips in-gamut colours', () {
      for (final hue in [0.0, 25, 90, 155, 200, 268, 330]) {
        final color = oklchColor(0.6, 0.1, hue.toDouble());
        final back = oklchOf(color);
        expect(back.l, closeTo(0.6, 0.002), reason: 'hue $hue');
        expect(back.c, closeTo(0.1, 0.002), reason: 'hue $hue');
        expect(back.h, closeTo(hue, 0.5), reason: 'hue $hue');
      }
    });

    test('greys have chroma ~0', () {
      expect(oklchOf(const Color(0xFF808080)).c, closeTo(0, 0.001));
    });
  });
}
