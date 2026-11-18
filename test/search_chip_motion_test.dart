// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/pages/global_search/search_result_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app({
  required bool selected,
  bool removable = false,
  bool still = false,
}) => MaterialApp(
  theme: ThemeData(extensions: [AppTokens.light()]),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(
      body: Center(
        child: SearchChip(
          label: 'Mara',
          selected: selected,
          onTap: () {},
          onClose: removable ? () {} : null,
        ),
      ),
    ),
  ),
);

Color _fill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(AnimatedContainer),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('selecting a chip fades the colours in 220 ms', (tester) async {
    await tester.pumpWidget(_app(selected: false));
    final before = _fill(tester);
    await tester.pumpWidget(_app(selected: true));
    await tester.pump(const Duration(milliseconds: 110));
    final middle = _fill(tester);
    await tester.pump(const Duration(milliseconds: 120));
    final after = _fill(tester);
    expect(middle, isNot(before));
    expect(middle, isNot(after));
    expect(after, AppTokens.light().accs);
  });

  testWidgets('with reduced motion the colours change at once', (tester) async {
    await tester.pumpWidget(_app(selected: false, still: true));
    await tester.pumpWidget(_app(selected: true, still: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_fill(tester), AppTokens.light().accs);
  });

  testWidgets('a chip that is added scales and fades in, 220 ms', (
    tester,
  ) async {
    await tester.pumpWidget(_app(selected: true, removable: true));
    final start = tester.widget<Opacity>(find.byType(Opacity));
    expect(start.opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 230));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('with reduced motion an added chip is there at once', (
    tester,
  ) async {
    await tester.pumpWidget(_app(selected: true, removable: true, still: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });
}
