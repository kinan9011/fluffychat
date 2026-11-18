// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/a11y_screens.dart';
import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  for (final scale in [1.3, 2.0]) {
    for (final screen in a11yScreens) {
      testWidgets('no overflow at text scale $scale: $screen', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previous);
        await harness.open(
          tester,
          path: a11yPath(screen, harness.room.id),
          width: 360,
          height: 640,
        );
        await harness.settle(tester, rounds: 4);
        FlutterError.onError = previous;
        expect(
          errors.map((e) => e.toString().split('\n').take(14).join('\n')),
          isEmpty,
        );
        await harness.finish(tester);
      });
    }
  }
}
