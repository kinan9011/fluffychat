// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app({required bool reduceMotion}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const Scaffold(body: Center(child: TypingAnimation())),
  ),
);

List<double> _heights(WidgetTester tester) => [
  for (final container in tester.widgetList<AnimatedContainer>(
    find.byType(AnimatedContainer),
  ))
    (container.constraints?.maxHeight ?? double.nan),
];

void main() {
  testWidgets('the dots move without the reduce motion setting', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: false));
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      seen.add(_heights(tester).join(','));
    }
    expect(seen.length, greaterThan(1));
  });

  testWidgets('with reduce motion the dots stay at rest and no timer runs', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    final first = _heights(tester).join(',');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(_heights(tester).join(','), first);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('turning reduce motion on while visible stops the timer', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_app(reduceMotion: true));
    await tester.pump(const Duration(seconds: 2));
    final settled = _heights(tester).join(',');
    await tester.pump(const Duration(seconds: 5));
    expect(_heights(tester).join(','), settled);
  });
}
