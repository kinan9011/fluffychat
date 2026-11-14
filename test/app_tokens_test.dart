// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Expected sRGB values of DESIGN.md section 6.1, computed with an independent
/// CSS Color 4 implementation (python), not with lib/utils/oklch.dart.
void expectColor(Color actual, int argb, String name) {
  final expected = Color(argb);
  final reason = '$name: expected $expected, got $actual';
  expect(actual.a * 255, closeTo(expected.a * 255, 1), reason: reason);
  expect(actual.r * 255, closeTo(expected.r * 255, 1), reason: reason);
  expect(actual.g * 255, closeTo(expected.g * 255, 1), reason: reason);
  expect(actual.b * 255, closeTo(expected.b * 255, 1), reason: reason);
}

void expectGradient(LinearGradient gradient, List<int> stops) {
  expect(gradient.colors, hasLength(3));
  expect(gradient.stops, [0, 0.5, 1]);
  for (var i = 0; i < 3; i++) {
    expectColor(gradient.colors[i], stops[i], 'wallG[$i]');
  }
}

void main() {
  group('default hue 268 matches DESIGN.md 6.1', () {
    test('light', () {
      final t = AppTokens.light();
      expectColor(t.bg, 0xFFF9FAFC, 'bg');
      expectColor(t.surf, 0xFFFFFFFF, 'surf');
      expectColor(t.surf2, 0xFFEEF0F4, 'surf2');
      expectColor(t.line, 0xFFE0E1E5, 'line');
      expectColor(t.fg, 0xFF1A1D24, 'fg');
      expectColor(t.mut, 0xFF60636C, 'mut');
      expectColor(t.acc, 0xFF4463C7, 'acc');
      expectColor(t.onacc, 0xFFFFFFFF, 'onacc');
      expectColor(t.accs, 0xFFE3EBFF, 'accs');
      expectColor(t.ok, 0xFF008B4F, 'ok');
      expectColor(t.warn, 0xFFBE7100, 'warn');
      expectColor(t.warnS, 0xFFFFECCD, 'warnS');
      expectColor(t.red, 0xFFD03739, 'red');
      expectColor(t.mbad, 0xFF72747B, 'mbad');
      expectColor(t.chip, 0x802F3C4A, 'chip');
      expectColor(t.shadow, 0x17141432, 'shadow');
      expectColor(t.outS, 0xFF4463C7, 'outS');
      expectColor(t.outFg, 0xFFFFFFFF, 'outFg');
      expectColor(t.outMut, 0xE6FFFFFF, 'outMut');
      expectColor(t.out, 0xFFDAE4FF, 'out');
      expectColor(t.inBubble, 0xFFFFFFFF, 'in');
      expectGradient(t.wallG, [0xFFBBECEE, 0xFFC3DEFB, 0xFFDACCF7]);
      expectColor(t.dot2, 0x8CA6C1DD, 'dot2');
      expectColor(t.glass, 0xBDFFFFFF, 'glass');
      expectColor(t.glassBd, 0x12141432, 'glassBd');
    });

    test('dark', () {
      final t = AppTokens.dark();
      expectColor(t.bg, 0xFF0D0F15, 'bg');
      expectColor(t.surf, 0xFF16181F, 'surf');
      expectColor(t.surf2, 0xFF21242C, 'surf2');
      expectColor(t.line, 0xFF282B33, 'line');
      expectColor(t.fg, 0xFFEDEEF2, 'fg');
      expectColor(t.mut, 0xFFA1A4AE, 'mut');
      expectColor(t.acc, 0xFF85A4FA, 'acc');
      expectColor(t.onacc, 0xFF0C111F, 'onacc');
      expectColor(t.accs, 0xFF232F4F, 'accs');
      expectColor(t.ok, 0xFF55C483, 'ok');
      expectColor(t.warn, 0xFFEEB154, 'warn');
      expectColor(t.warnS, 0xFF3C2A0E, 'warnS');
      expectColor(t.red, 0xFFF66D67, 'red');
      expectColor(t.mbad, 0xFF53555B, 'mbad');
      expectColor(t.chip, 0xBF2A2D38, 'chip');
      expectColor(t.shadow, 0x66000000, 'shadow');
      expectColor(t.outS, 0xFF3F5BB8, 'outS');
      expectColor(t.outFg, 0xFFFFFFFF, 'outFg');
      expectColor(t.outMut, 0xE0FFFFFF, 'outMut');
      expectColor(t.out, 0xFF293B74, 'out');
      expectColor(t.inBubble, 0xFF1F212A, 'in');
      expectGradient(t.wallG, [0xFF023538, 0xFF0A2036, 0xFF1F1332]);
      expectColor(t.dot2, 0x73334A62, 'dot2');
      expectColor(t.glass, 0xBD1C1F27, 'glass');
      expectColor(t.glassBd, 0x14FFFFFF, 'glassBd');
    });
  });

  group('non-default hues match an independent reference', () {
    // light: acc (= outS), accs, out; dark: acc, onacc, accs, outS, out.
    final reference = <double, List<int>>{
      200: [
        0xFF00767B,
        0xFFD1F3F4,
        0xFFC3EEF0,
        0xFF00BFC6,
        0xFF001517,
        0xFF00383B,
        0xFF007176,
        0xFF00494D,
      ],
      155: [
        0xFF007A44,
        0xFFDAF3E1,
        0xFFCEEED8,
        0xFF5BC083,
        0xFF06150C,
        0xFF123923,
        0xFF007742,
        0xFF004D29,
      ],
      25: [
        0xFFB63B39,
        0xFFFFE4E1,
        0xFFFFDBD7,
        0xFFEE857E,
        0xFF1D0C0B,
        0xFF4A2321,
        0xFFA83634,
        0xFF6B2523,
      ],
      330: [
        0xFF9C4297,
        0xFFF9E3F7,
        0xFFF7DAF3,
        0xFFD588CE,
        0xFF190D18,
        0xFF41243F,
        0xFF903D8B,
        0xFF5C2958,
      ],
    };
    for (final entry in reference.entries) {
      test('hue ${entry.key}', () {
        final r = entry.value;
        final light = AppTokens.light(hue: entry.key);
        expectColor(light.acc, r[0], 'light acc');
        expectColor(light.outS, r[0], 'light outS');
        expectColor(light.accs, r[1], 'light accs');
        expectColor(light.out, r[2], 'light out');
        final dark = AppTokens.dark(hue: entry.key);
        expectColor(dark.acc, r[3], 'dark acc');
        expectColor(dark.onacc, r[4], 'dark onacc');
        expectColor(dark.accs, r[5], 'dark accs');
        expectColor(dark.outS, r[6], 'dark outS');
        expectColor(dark.out, r[7], 'dark out');
      });
    }

    test('hue 268 is never darkened by the contrast guard', () {
      expectColor(AppTokens.light().acc, 0xFF4463C7, 'acc');
    });
  });

  group('accent hues', () {
    test('the five options are exposed, 268 is the default', () {
      expect(AppTokens.accentHues, [268, 200, 155, 25, 330]);
      expect(defaultAccentHue, 268);
    });

    test('derivation is deterministic', () {
      for (final hue in AppTokens.accentHues) {
        expect(AppTokens.light(hue: hue), AppTokens.light(hue: hue));
        expect(AppTokens.dark(hue: hue), AppTokens.dark(hue: hue));
      }
    });

    test('only accent tokens change with the hue', () {
      final base = AppTokens.light();
      final other = AppTokens.light(hue: 25);
      expect(other.acc, isNot(base.acc));
      expect(other.accs, isNot(base.accs));
      expect(other.outS, isNot(base.outS));
      expect(other.out, isNot(base.out));
      expect(other.bg, base.bg);
      expect(other.surf2, base.surf2);
      expect(other.fg, base.fg);
      expect(other.red, base.red);
      expect(other.glass, base.glass);
    });

    test('dark onacc follows the hue', () {
      expect(AppTokens.dark(hue: 25).onacc, isNot(AppTokens.dark().onacc));
    });

    test('invalid hues fall back to a valid token set', () {
      for (final hue in [double.nan, double.infinity, -90.0, 725.0]) {
        final tokens = AppTokens.light(hue: hue);
        expect(tokens.acc.a, 1);
      }
      expect(AppTokens.light(hue: 628), AppTokens.light(hue: 268));
    });
  });

  group('contrast (DESIGN 13: >= 4.5:1)', () {
    for (final hue in AppTokens.accentHues) {
      for (final dark in [false, true]) {
        final label = '${dark ? 'dark' : 'light'} hue $hue';
        test(label, () {
          final t = dark ? AppTokens.dark(hue: hue) : AppTokens.light(hue: hue);
          final checks = {
            'fg on bg': wcagContrast(t.fg, t.bg),
            'fg on surf': wcagContrast(t.fg, t.surf),
            'fg on surf2': wcagContrast(t.fg, t.surf2),
            'onacc on acc': wcagContrast(t.onacc, t.acc),
            'outFg on outS': wcagContrast(t.outFg, t.outS),
            'mut on bg': wcagContrast(t.mut, t.bg),
            'mut on surf': wcagContrast(t.mut, t.surf),
            'acc on bg': wcagContrast(t.acc, t.bg),
            'acc on surf': wcagContrast(t.acc, t.surf),
            'acc on accs': wcagContrast(t.acc, t.accs),
            'fg on out': wcagContrast(t.fg, t.out),
          };
          for (final entry in checks.entries) {
            expect(
              entry.value,
              greaterThanOrEqualTo(4.5),
              reason: '${entry.key} in $label',
            );
          }
        });
      }
    }
  });

  group('DESIGN 13 pairs fixed in W02A (decision log 13)', () {
    for (final dark in [false, true]) {
      test('${dark ? 'dark' : 'light'}: white on mbad is >= 4.5:1', () {
        final t = dark ? AppTokens.dark() : AppTokens.light();
        expect(wcagContrast(Colors.white, t.mbad), greaterThanOrEqualTo(4.5));
      });

      test(
        '${dark ? 'dark' : 'light'}: outMut on outS is >= 4.5:1 for every hue',
        () {
          for (var hue = 0; hue < 360; hue++) {
            final t = dark
                ? AppTokens.dark(hue: hue.toDouble())
                : AppTokens.light(hue: hue.toDouble());
            expect(
              wcagContrast(t.outMut, t.outS),
              greaterThanOrEqualTo(4.5),
              reason: 'hue $hue',
            );
          }
        },
      );
    }

    test('white initials on the avatar fill are >= 4.5:1 for every hue', () {
      for (var hue = 0; hue < 360; hue++) {
        expect(
          wcagContrast(Colors.white, avatarColorForHue(hue.toDouble())),
          greaterThanOrEqualTo(4.5),
          reason: 'hue $hue',
        );
      }
    });
  });

  group('DESIGN 13 non-text pairs (decision log 15): >= 3:1', () {
    // Status colours are used for icons, dots and borders, never for body
    // text on these backgrounds. Text on red uses onRed.
    test('light', () {
      final t = AppTokens.light();
      expect(wcagContrast(t.warn, t.warnS), greaterThanOrEqualTo(3));
      expect(wcagContrast(t.ok, t.bg), greaterThanOrEqualTo(3));
      expect(wcagContrast(t.warn, t.bg), greaterThanOrEqualTo(3));
    });

    test('dark: text on red uses the dark onRed colour', () {
      final t = AppTokens.dark();
      expect(t.onRed, oklchColor(0.18, 0.03, 25));
      expect(wcagContrast(t.onRed, t.red), greaterThanOrEqualTo(4.5));
    });
  });

  group('onRed (text on --red)', () {
    test('is >= 4.5:1 on red in both themes for every hue', () {
      for (var hue = 0; hue < 360; hue++) {
        for (final t in [
          AppTokens.light(hue: hue.toDouble()),
          AppTokens.dark(hue: hue.toDouble()),
        ]) {
          expect(
            wcagContrast(t.onRed, t.red),
            greaterThanOrEqualTo(4.5),
            reason: 'hue $hue',
          );
        }
      }
    });

    test('light stays white, dark is dark', () {
      expect(AppTokens.light().onRed, Colors.white);
      expect(AppTokens.dark().onRed.computeLuminance(), lessThan(0.05));
    });

    test('copyWith and lerp carry it', () {
      final light = AppTokens.light();
      final dark = AppTokens.dark();
      expect(light.copyWith(onRed: Colors.black).onRed, Colors.black);
      expect(light.copyWith(onRed: Colors.black), isNot(light));
      expect(light.lerp(dark, 1).onRed, dark.onRed);
    });
  });

  group('ThemeExtension', () {
    test('copyWith replaces only the given field', () {
      final base = AppTokens.light();
      final changed = base.copyWith(acc: Colors.red);
      expect(changed.acc, Colors.red);
      expect(changed.bg, base.bg);
      expect(changed.wallG, base.wallG);
    });

    test('lerp interpolates colours and gradients', () {
      final a = AppTokens.light();
      final b = AppTokens.dark();
      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
      final mid = a.lerp(b, 0.5);
      expect(mid.bg, Color.lerp(a.bg, b.bg, 0.5));
      expect(
        mid.wallG.colors.first,
        Color.lerp(a.wallG.colors.first, b.wallG.colors.first, 0.5),
      );
      expect(a.lerp(null, 0.5), a);
    });

    testWidgets(
      'of(context) reads the theme extension, falls back by brightness',
      (tester) async {
        late AppTokens fromExtension;
        late AppTokens fromFallback;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [AppTokens.dark(hue: 25)]),
            home: Builder(
              builder: (context) {
                fromExtension = AppTokens.of(context);
                return Theme(
                  data: ThemeData(brightness: Brightness.dark),
                  child: Builder(
                    builder: (context) {
                      fromFallback = AppTokens.of(context);
                      return const SizedBox();
                    },
                  ),
                );
              },
            ),
          ),
        );
        expect(fromExtension, AppTokens.dark(hue: 25));
        expect(fromFallback, AppTokens.dark());
      },
    );
  });
}
