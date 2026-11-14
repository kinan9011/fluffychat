// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/oklch.dart';
import 'package:material_ui/material_ui.dart';

const double defaultAccentHue = 268;

double normalizeHue(double hue) => hue.isFinite ? hue % 360 : defaultAccentHue;

/// Colour tokens of DESIGN.md section 6.1. Only [acc], [onacc] (dark), [accs],
/// [outS] and [out] depend on the accent hue; neutrals stay at hue 270.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  static const accentHues = <double>[268, 200, 155, 25, 330];

  final Color bg;
  final Color surf;
  final Color surf2;
  final Color line;
  final Color fg;
  final Color mut;
  final Color acc;
  final Color onacc;
  final Color accs;
  final Color ok;
  final Color warn;
  final Color warnS;
  final Color red;
  final Color onRed;
  final Color mbad;
  final Color chip;
  final Color shadow;
  final Color outS;
  final Color outFg;
  final Color outMut;
  final Color out;
  final Color inBubble;
  final LinearGradient wallG;
  final Color dot2;
  final Color glass;
  final Color glassBd;

  const AppTokens({
    required this.bg,
    required this.surf,
    required this.surf2,
    required this.line,
    required this.fg,
    required this.mut,
    required this.acc,
    required this.onacc,
    required this.accs,
    required this.ok,
    required this.warn,
    required this.warnS,
    required this.red,
    required this.onRed,
    required this.mbad,
    required this.chip,
    required this.shadow,
    required this.outS,
    required this.outFg,
    required this.outMut,
    required this.out,
    required this.inBubble,
    required this.wallG,
    required this.dot2,
    required this.glass,
    required this.glassBd,
  });

  factory AppTokens.light({double hue = defaultAccentHue}) {
    final h = normalizeHue(hue);
    final accs = oklchColor(0.94, 0.035, h);
    final acc = _lightAccent(h, accs);
    return AppTokens(
      bg: oklchColor(0.985, 0.003, 270),
      surf: const Color(0xFFFFFFFF),
      surf2: oklchColor(0.955, 0.006, 270),
      line: oklchColor(0.91, 0.006, 270),
      fg: oklchColor(0.23, 0.015, 270),
      mut: oklchColor(0.50, 0.015, 270),
      acc: acc,
      onacc: const Color(0xFFFFFFFF),
      accs: accs,
      ok: oklchColor(0.56, 0.14, 155),
      warn: oklchColor(0.62, 0.14, 65),
      warnS: oklchColor(0.95, 0.05, 80),
      red: oklchColor(0.57, 0.19, 25),
      onRed: const Color(0xFFFFFFFF),
      mbad: oklchColor(0.56, 0.01, 270),
      chip: oklchColor(0.35, 0.03, 250, 0.5),
      shadow: const Color.fromRGBO(20, 20, 50, 0.09),
      outS: acc,
      outFg: const Color(0xFFFFFFFF),
      outMut: const Color.fromRGBO(255, 255, 255, 0.90),
      out: oklchColor(0.92, 0.045, h),
      inBubble: const Color(0xFFFFFFFF),
      wallG: _wallGradient(
        oklchColor(0.91, 0.05, 200),
        oklchColor(0.89, 0.05, 250),
        oklchColor(0.87, 0.06, 300),
      ),
      dot2: oklchColor(0.8, 0.05, 250, 0.55),
      glass: const Color.fromRGBO(255, 255, 255, 0.74),
      glassBd: const Color.fromRGBO(20, 20, 50, 0.07),
    );
  }

  factory AppTokens.dark({double hue = defaultAccentHue}) {
    final h = normalizeHue(hue);
    return AppTokens(
      bg: oklchColor(0.17, 0.012, 270),
      surf: oklchColor(0.21, 0.014, 270),
      surf2: oklchColor(0.26, 0.016, 270),
      line: oklchColor(0.29, 0.014, 270),
      fg: oklchColor(0.95, 0.005, 270),
      mut: oklchColor(0.72, 0.015, 270),
      acc: oklchColor(0.73, 0.13, h),
      onacc: oklchColor(0.18, 0.03, h),
      accs: oklchColor(0.31, 0.06, h),
      ok: oklchColor(0.74, 0.14, 155),
      warn: oklchColor(0.80, 0.13, 75),
      warnS: oklchColor(0.30, 0.05, 75),
      red: oklchColor(0.70, 0.17, 25),
      onRed: oklchColor(0.18, 0.03, 25),
      mbad: oklchColor(0.45, 0.01, 270),
      chip: oklchColor(0.30, 0.02, 270, 0.75),
      shadow: const Color.fromRGBO(0, 0, 0, 0.4),
      outS: oklchColor(0.50, 0.15, h),
      outFg: const Color(0xFFFFFFFF),
      outMut: const Color.fromRGBO(255, 255, 255, 0.88),
      out: oklchColor(0.37, 0.10, h),
      inBubble: oklchColor(0.25, 0.016, 270),
      wallG: _wallGradient(
        oklchColor(0.30, 0.05, 200),
        oklchColor(0.24, 0.05, 250),
        oklchColor(0.22, 0.06, 300),
      ),
      dot2: oklchColor(0.40, 0.05, 250, 0.45),
      glass: oklchColor(0.24, 0.016, 270, 0.74),
      glassBd: const Color.fromRGBO(255, 255, 255, 0.08),
    );
  }

  /// Accent text sits on the accent tint (mention pill, selected tab). Light
  /// green and cyan hues miss 4.5:1 at the specified lightness, so darken
  /// until it holds. Hue 268 is unchanged.
  static Color _lightAccent(double hue, Color tint) {
    var lightness = 0.53;
    var color = oklchColor(lightness, 0.16, hue);
    while (lightness > 0.4 && wcagContrast(color, tint) < 4.5) {
      lightness -= 0.005;
      color = oklchColor(lightness, 0.16, hue);
    }
    return color;
  }

  static LinearGradient _wallGradient(Color a, Color b, Color c) =>
      LinearGradient(
        // CSS linear-gradient(160deg) points down and slightly right.
        begin: const Alignment(-0.34, -0.94),
        end: const Alignment(0.34, 0.94),
        colors: [a, b, c],
        stops: const [0, 0.5, 1],
      );

  static AppTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark()
            : AppTokens.light());
  }

  List<Object> get _fields => [
    bg,
    surf,
    surf2,
    line,
    fg,
    mut,
    acc,
    onacc,
    accs,
    ok,
    warn,
    warnS,
    red,
    onRed,
    mbad,
    chip,
    shadow,
    outS,
    outFg,
    outMut,
    out,
    inBubble,
    wallG,
    dot2,
    glass,
    glassBd,
  ];

  @override
  bool operator ==(Object other) =>
      other is AppTokens &&
      _fields.indexed.every((e) => e.$2 == other._fields[e.$1]);

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  AppTokens copyWith({
    Color? bg,
    Color? surf,
    Color? surf2,
    Color? line,
    Color? fg,
    Color? mut,
    Color? acc,
    Color? onacc,
    Color? accs,
    Color? ok,
    Color? warn,
    Color? warnS,
    Color? red,
    Color? onRed,
    Color? mbad,
    Color? chip,
    Color? shadow,
    Color? outS,
    Color? outFg,
    Color? outMut,
    Color? out,
    Color? inBubble,
    LinearGradient? wallG,
    Color? dot2,
    Color? glass,
    Color? glassBd,
  }) => AppTokens(
    bg: bg ?? this.bg,
    surf: surf ?? this.surf,
    surf2: surf2 ?? this.surf2,
    line: line ?? this.line,
    fg: fg ?? this.fg,
    mut: mut ?? this.mut,
    acc: acc ?? this.acc,
    onacc: onacc ?? this.onacc,
    accs: accs ?? this.accs,
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
    warnS: warnS ?? this.warnS,
    red: red ?? this.red,
    onRed: onRed ?? this.onRed,
    mbad: mbad ?? this.mbad,
    chip: chip ?? this.chip,
    shadow: shadow ?? this.shadow,
    outS: outS ?? this.outS,
    outFg: outFg ?? this.outFg,
    outMut: outMut ?? this.outMut,
    out: out ?? this.out,
    inBubble: inBubble ?? this.inBubble,
    wallG: wallG ?? this.wallG,
    dot2: dot2 ?? this.dot2,
    glass: glass ?? this.glass,
    glassBd: glassBd ?? this.glassBd,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      bg: c(bg, other.bg),
      surf: c(surf, other.surf),
      surf2: c(surf2, other.surf2),
      line: c(line, other.line),
      fg: c(fg, other.fg),
      mut: c(mut, other.mut),
      acc: c(acc, other.acc),
      onacc: c(onacc, other.onacc),
      accs: c(accs, other.accs),
      ok: c(ok, other.ok),
      warn: c(warn, other.warn),
      warnS: c(warnS, other.warnS),
      red: c(red, other.red),
      onRed: c(onRed, other.onRed),
      mbad: c(mbad, other.mbad),
      chip: c(chip, other.chip),
      shadow: c(shadow, other.shadow),
      outS: c(outS, other.outS),
      outFg: c(outFg, other.outFg),
      outMut: c(outMut, other.outMut),
      out: c(out, other.out),
      inBubble: c(inBubble, other.inBubble),
      wallG: LinearGradient.lerp(wallG, other.wallG, t)!,
      dot2: c(dot2, other.dot2),
      glass: c(glass, other.glass),
      glassBd: c(glassBd, other.glassBd),
    );
  }
}
