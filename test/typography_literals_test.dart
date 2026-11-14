// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/design_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the mono font family literal lives only in design_constants', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('config/design_constants.dart'))
        .where((f) => f.readAsStringSync().contains("'JetBrainsMono'"))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });

  test('ltr isolates the text with U+2066 ... U+2069', () {
    final isolated = AppTypography.ltr('@a:b');
    expect(isolated.codeUnits.first, 0x2066);
    expect(isolated.codeUnits.last, 0x2069);
    expect(isolated.substring(1, isolated.length - 1), '@a:b');
  });

  test('selectable text is never wrapped in the bidi isolate (L5)', () {
    final selectable = RegExp(r'SelectableText\(\s*AppTypography\.ltr\(');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => selectable.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'copying would add U+2066 / U+2069');
  });

  test('mono style uses the bundled family', () {
    expect(AppTypography.mono.fontFamily, 'JetBrainsMono');
  });
}
