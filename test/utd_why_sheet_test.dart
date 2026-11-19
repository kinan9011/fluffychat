// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/chat/utd_why_sheet.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  setUpAll(prepareTestClient);

  testWidgets('the sheet explains three reasons and offers two actions', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      const UtdWhySheet(),
      size: const Size(400, 700),
    );
    for (final text in [
      "Why can't I read this?",
      'Sent before you joined',
      'Keys not shared yet',
      'This device is not verified',
      'Verify this device',
      'Restore from key backup',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('goldens in light and dark', (tester) async {
    for (final variant in goldenVariants.where((v) => !v.rtl)) {
      await pumpGoldenWidget(
        tester,
        const Align(alignment: Alignment.bottomCenter, child: UtdWhySheet()),
        brightness: variant.brightness,
        size: const Size(400, 640),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/utd_why_sheet_${variant.suffix}.png'),
      );
    }
  });

  test('the sheet never touches trust and shows nothing of the event', () {
    final source = File('lib/pages/chat/utd_why_sheet.dart')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    for (final identifier in [
      'setVerified',
      'setBlocked',
      'startVerification',
      'crossSigning',
      'openSSSS',
      'bootstrap',
      'calcLocalizedBodyFallback',
      'event.body',
      'senderFromMemoryOrFallback',
      'calcDisplayname',
      'content[',
    ]) {
      expect(source, isNot(contains(identifier)), reason: identifier);
    }
  });
}
