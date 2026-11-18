// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'utils/a11y_screens.dart';
import 'utils/chat_page_harness.dart';

/// Screens that fail a guideline for a reason that is not a defect, with that
/// reason. An entry without a reason is not allowed.
const _tapTargetExclusions = <String, String>{
  '/rooms/{room}/details':
      'the chat description is a read-only selectable text field, not a '
      'control; the guideline counts its long-press for text selection',
};
const _labelExclusions = <String, String>{};

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  for (final screen in a11yScreens) {
    testWidgets('44 px targets and labels: $screen', (tester) async {
      final handle = tester.ensureSemantics();
      await harness.open(
        tester,
        path: a11yPath(screen, harness.room.id),
        height: 800,
      );
      await harness.settle(tester, rounds: 4);
      if (!_tapTargetExclusions.containsKey(screen)) {
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      }
      if (!_labelExclusions.containsKey(screen)) {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
      await harness.finish(tester);
    });
  }

  test('every exclusion carries a reason', () {
    for (final reason in [
      ..._tapTargetExclusions.values,
      ..._labelExclusions.values,
    ]) {
      expect(reason.trim().length, greaterThan(15));
    }
  });
}
