// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/glass_policy.dart';

void main() {
  group('glassIsSolid truth table', () {
    for (final reduce in [false, true]) {
      for (final contrast in [false, true]) {
        for (final mode in GlassMode.values) {
          for (final lowEnd in [false, true]) {
            for (final requested in [false, true]) {
              test('reduce=$reduce contrast=$contrast mode=${mode.name} '
                  'lowEnd=$lowEnd requested=$requested', () {
                final expected =
                    requested ||
                    reduce ||
                    contrast ||
                    mode == GlassMode.lite ||
                    (mode == GlassMode.auto && lowEnd);
                expect(
                  glassIsSolid(
                    reduceTransparency: reduce,
                    highContrast: contrast,
                    mode: mode,
                    lowEnd: lowEnd,
                    solidRequested: requested,
                  ),
                  expected,
                );
              });
            }
          }
        }
      }
    }

    test(
      'full blurs on a low end device unless an accessibility flag wins',
      () {
        bool solid({bool reduce = false, bool contrast = false}) =>
            glassIsSolid(
              reduceTransparency: reduce,
              highContrast: contrast,
              mode: GlassMode.full,
              lowEnd: true,
            );
        expect(solid(), isFalse);
        expect(solid(reduce: true), isTrue);
        expect(solid(contrast: true), isTrue);
      },
    );
  });

  group('detectLowEnd', () {
    test('a phone browser is low end, a desktop browser is not', () {
      bool web(TargetPlatform p) =>
          detectLowEnd(isWeb: true, platform: p, processors: 16);
      expect(web(TargetPlatform.android), isTrue);
      expect(web(TargetPlatform.iOS), isTrue);
      expect(web(TargetPlatform.linux), isFalse);
      expect(web(TargetPlatform.macOS), isFalse);
      expect(web(TargetPlatform.windows), isFalse);
    });

    test('native: four cores or fewer is low end', () {
      bool native(int cores) => detectLowEnd(
        isWeb: false,
        platform: TargetPlatform.android,
        processors: cores,
      );
      expect(native(2), isTrue);
      expect(native(4), isTrue);
      expect(native(5), isFalse);
      expect(native(8), isFalse);
    });
  });

  group('GlassMode.parse', () {
    test('known names, anything else is auto', () {
      expect(GlassMode.parse('full'), GlassMode.full);
      expect(GlassMode.parse('lite'), GlassMode.lite);
      expect(GlassMode.parse('auto'), GlassMode.auto);
      for (final value in [null, 1, 'LITE', '', <String>[], 'x' * 1000]) {
        expect(GlassMode.parse(value), GlassMode.auto, reason: '$value');
      }
    });
  });
}
