// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

double _finiteOr0(double value) => value.isFinite ? value : 0;

double _toSrgb(double linear) {
  final value = linear.clamp(0.0, 1.0);
  return value <= 0.0031308
      ? 12.92 * value
      : 1.055 * math.pow(value, 1 / 2.4) - 0.055;
}

double _toLinear(double srgb) => srgb <= 0.04045
    ? srgb / 12.92
    : math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();

(double, double, double) _linearRgb(double l, double c, double hue) {
  final radians = hue * math.pi / 180;
  final a = c * math.cos(radians);
  final b = c * math.sin(radians);
  final lc = math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final mc = math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final sc = math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
  return (
    4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
    -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
    -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc,
  );
}

bool _inGamut((double, double, double) rgb) {
  const epsilon = 1e-6;
  bool ok(double v) => v >= -epsilon && v <= 1 + epsilon;
  return ok(rgb.$1) && ok(rgb.$2) && ok(rgb.$3);
}

/// Converts an OKLCH colour to sRGB. Out-of-gamut colours keep lightness and
/// hue and lose chroma (bisection), so a hue never shifts. Non-finite input
/// is treated as 0 because hues come from untrusted places (config, hashes).
Color oklchColor(double l, double c, double h, [double alpha = 1]) {
  final lightness = _finiteOr0(l);
  final alphaValue = alpha.isFinite ? alpha.clamp(0.0, 1.0) : 1.0;
  if (lightness >= 1) {
    return Color.from(alpha: alphaValue, red: 1, green: 1, blue: 1);
  }
  if (lightness <= 0) {
    return Color.from(alpha: alphaValue, red: 0, green: 0, blue: 0);
  }

  final hue = _finiteOr0(h) % 360;
  var chroma = math.max(0.0, _finiteOr0(c));
  var rgb = _linearRgb(lightness, chroma, hue);
  if (!_inGamut(rgb)) {
    var low = 0.0;
    var high = chroma;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (_inGamut(_linearRgb(lightness, mid, hue))) {
        low = mid;
        continue;
      }
      high = mid;
    }
    chroma = low;
    rgb = _linearRgb(lightness, chroma, hue);
  }
  return Color.from(
    alpha: alphaValue,
    red: _toSrgb(rgb.$1),
    green: _toSrgb(rgb.$2),
    blue: _toSrgb(rgb.$3),
  );
}

/// Inverse of [oklchColor], used to turn a user-picked colour into a hue.
({double l, double c, double h}) oklchOf(Color color) {
  final r = _toLinear(color.r.clamp(0.0, 1.0));
  final g = _toLinear(color.g.clamp(0.0, 1.0));
  final b = _toLinear(color.b.clamp(0.0, 1.0));
  final l = math.pow(
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    1 / 3,
  );
  final m = math.pow(
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    1 / 3,
  );
  final s = math.pow(
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
    1 / 3,
  );
  final lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  final a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  final hue = math.atan2(bb, a) * 180 / math.pi;
  return (
    l: lightness,
    c: math.sqrt(a * a + bb * bb),
    h: hue < 0 ? hue + 360 : hue,
  );
}

double _luminance(Color color) =>
    0.2126 * _toLinear(color.r) +
    0.7152 * _toLinear(color.g) +
    0.0722 * _toLinear(color.b);

/// WCAG 2.x contrast ratio; a translucent [foreground] is composited over
/// [background] first.
double wcagContrast(Color foreground, Color background) {
  final a = _luminance(Color.alphaBlend(foreground, background));
  final b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}
