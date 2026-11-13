// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('colorHue', () {
    test('matches fixed vectors (same on every platform and run)', () {
      expect(''.colorHue, 341);
      expect('a'.colorHue, 190);
      expect('@alice:example.org'.colorHue, 191);
      expect('@bob:example.org'.colorHue, 306);
      expect('Anna Kim'.colorHue, 182);
      expect('日本語'.colorHue, 316);
      expect('😀'.colorHue, 105);
    });

    test('is deterministic and within 0..359', () {
      for (var i = 0; i < 500; i++) {
        final id = '@user$i:example.org';
        expect(id.colorHue, id.colorHue);
        expect(id.colorHue, inInclusiveRange(0, 359));
      }
    });

    test('spreads ids over the hue circle', () {
      final hues = {
        for (var i = 0; i < 200; i++) '@user$i:example.org'.colorHue,
      };
      expect(hues.length, greaterThan(100));
    });

    test('very long untrusted input is capped and stays cheap', () {
      final huge = 'x' * 5000000;
      final stopwatch = Stopwatch()..start();
      final hue = huge.colorHue;
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(hue, ('x' * 1024).colorHue);
    });
  });

  group('colours', () {
    test('avatar colour is oklch(0.62 0.12 hue)', () {
      expect('@alice:example.org'.avatarColor, oklchColor(0.62, 0.12, 191));
    });

    test('name colour uses L 0.52 (light) and 0.76 (dark) at chroma 0.14', () {
      expect(
        '@alice:example.org'.nameColor(Brightness.light),
        oklchColor(0.52, 0.14, 191),
      );
      expect(
        '@alice:example.org'.nameColor(Brightness.dark),
        oklchColor(0.76, 0.14, 191),
      );
    });

    test('white avatar initials stay legible as large text (>= 3:1)', () {
      for (var hue = 0; hue < 360; hue++) {
        final avatar = oklchColor(0.62, 0.12, hue.toDouble());
        expect(
          wcagContrast(Colors.white, avatar),
          greaterThanOrEqualTo(3),
          reason: 'hue $hue',
        );
      }
    });

    test('name colours stay legible on bubbles for every hue (>= 4.5:1)', () {
      final light = AppTokens.light();
      final dark = AppTokens.dark();
      final idByHue = <double, String>{};
      for (var i = 0; idByHue.length < 360 && i < 100000; i++) {
        final id = '@u$i:example.org';
        idByHue.putIfAbsent(id.colorHue, () => id);
      }
      expect(idByHue, hasLength(360));
      for (final MapEntry(key: hue, value: id) in idByHue.entries) {
        expect(
          wcagContrast(id.nameColor(Brightness.light), light.surf),
          greaterThanOrEqualTo(4.5),
          reason: 'light hue $hue',
        );
        expect(
          wcagContrast(id.nameColor(Brightness.dark), dark.inBubble),
          greaterThanOrEqualTo(4.5),
          reason: 'dark hue $hue',
        );
      }
    });
  });
}
