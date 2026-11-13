// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellMode.forWidth (DESIGN 12)', () {
    final expected = <double, ShellMode>{
      320: ShellMode.mobile,
      599: ShellMode.mobile,
      600: ShellMode.twoPane,
      899: ShellMode.twoPane,
      900: ShellMode.rail,
      1279: ShellMode.rail,
      1280: ShellMode.wide,
      2560: ShellMode.wide,
    };
    expected.forEach((width, mode) {
      test('$width -> $mode', () => expect(ShellMode.forWidth(width), mode));
    });

    test('panel sizes follow the spec', () {
      expect(FluffyThemes.navRailWidth, 76);
      expect(FluffyThemes.listColumnWidth, 350);
      expect(FluffyThemes.detailsPanelWidth, 340);
    });

    test('the rail starts at 900 px and the details panel at 1280 px', () {
      expect(
        [
          for (final w in [599.0, 600.0, 899.0, 900.0, 1279.0, 1280.0])
            ShellMode.forWidth(w).hasRail,
        ],
        [false, false, false, true, true, true],
      );
      expect(
        [
          for (final w in [599.0, 600.0, 1279.0, 1280.0])
            FluffyThemes.isThreeColumnModeByWidth(w),
        ],
        [false, false, false, true],
      );
      expect(
        [
          for (final w in [599.0, 600.0, 899.0, 900.0])
            FluffyThemes.isColumnModeByWidth(w),
        ],
        [false, true, true, true],
      );
    });
  });
}
