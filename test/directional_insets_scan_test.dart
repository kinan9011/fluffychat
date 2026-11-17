// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the W07 screens place their padding with start and end, so right to '
      'left languages mirror', () {
    final files = [
      for (final dir in ['lib/pages/chat/poll_composer', 'lib/pages/topics'])
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      File('lib/pages/chat/retention_sheet.dart'),
      File('lib/pages/settings_security/privacy_toggles.dart'),
    ];
    final absolute = RegExp(
      r'EdgeInsets\.(only\([^)]*\b(left|right):|fromLTRB)|Alignment\.(centerLeft|centerRight)',
    );
    for (final file in files) {
      expect(
        absolute.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });
}
