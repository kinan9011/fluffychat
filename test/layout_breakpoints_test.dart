// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/themes.dart';

Future<({bool column, bool three})> _modeAt(
  WidgetTester tester,
  double width,
  double height,
) async {
  var column = false;
  var three = false;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(width, height)),
      child: Builder(
        builder: (context) {
          column = FluffyThemes.isColumnMode(context);
          three = FluffyThemes.isThreeColumnMode(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return (column: column, three: three);
}

void main() {
  group('DESIGN 12 widths at a normal height', () {
    const cases = <(double, bool, bool)>[
      (320, false, false),
      (599, false, false),
      (600, true, false),
      (899, true, false),
      (900, true, false),
      (1279, true, false),
      (1280, true, true),
      (1920, true, true),
    ];
    for (final (width, column, three) in cases) {
      testWidgets('${width.toInt()} x 800', (tester) async {
        final mode = await _modeAt(tester, width, 800);
        expect(mode.column, column);
        expect(mode.three, three);
      });
    }
  });

  group('compact height (landscape phone) keeps the mobile shell', () {
    testWidgets('844 x 390 is not a two pane layout', (tester) async {
      final mode = await _modeAt(tester, 844, 390);
      expect(mode.column, isFalse);
      expect(mode.three, isFalse);
    });

    testWidgets('the limit is 480: 479 is compact, 480 is not', (tester) async {
      expect((await _modeAt(tester, 900, 479)).column, isFalse);
      expect((await _modeAt(tester, 900, 480)).column, isTrue);
    });

    testWidgets('a wide but short desktop window is mobile too', (
      tester,
    ) async {
      final mode = await _modeAt(tester, 1600, 400);
      expect(mode.column, isFalse);
      expect(mode.three, isFalse);
    });

    testWidgets('the shell mode follows the same rule', (tester) async {
      expect(ShellMode.forSize(const Size(844, 390)), ShellMode.mobile);
      expect(ShellMode.forSize(const Size(844, 480)), ShellMode.twoPane);
      expect(ShellMode.forSize(const Size(1600, 400)), ShellMode.mobile);
      expect(ShellMode.forSize(const Size(1600, 900)), ShellMode.wide);
      expect(ShellMode.forSize(const Size(700, 800)), ShellMode.twoPane);
    });

    testWidgets('the width based helper used by login keeps its rule', (
      tester,
    ) async {
      expect(FluffyThemes.isColumnModeByWidth(600), isTrue);
      expect(FluffyThemes.isColumnModeByWidth(599), isFalse);
    });
  });
}
