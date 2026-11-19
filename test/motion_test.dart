// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/utils/motion.dart';

Future<Duration> _resolve(WidgetTester tester, bool reduce) async {
  late Duration result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Builder(
        builder: (context) {
          result = motionDuration(context, const Duration(milliseconds: 250));
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('without reduce motion the duration is unchanged', (
    tester,
  ) async {
    expect(await _resolve(tester, false), const Duration(milliseconds: 250));
  });

  testWidgets('with reduce motion it is practically none, never zero', (
    tester,
  ) async {
    final duration = await _resolve(tester, true);
    expect(duration, reducedMotionDuration);
    expect(duration, greaterThan(Duration.zero));
    expect(duration, lessThanOrEqualTo(const Duration(milliseconds: 5)));
  });

  testWidgets('an AnimatedSize with the reduced duration lays out cleanly', (
    tester,
  ) async {
    var tall = false;
    late StateSetter setState;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, set) {
              setState = set;
              return Align(
                alignment: Alignment.topLeft,
                child: AnimatedSize(
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 250),
                  ),
                  child: SizedBox(
                    key: const Key('box'),
                    height: tall ? 200 : 50,
                    width: 50,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    setState(() => tall = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('box'))).height, 200);
  });
}
