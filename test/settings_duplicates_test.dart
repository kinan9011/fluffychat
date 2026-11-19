// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an app setting is a row in one settings page only', () {
    final rows = <String, List<String>>{};
    final pattern = RegExp(r'setting:\s*AppSettings\.(\w+)');
    for (final entity in Directory('lib/pages').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.path.startsWith('lib/pages/settings')) continue;
      for (final match in pattern.allMatches(entity.readAsStringSync())) {
        rows.putIfAbsent(match.group(1)!, () => []).add(entity.path);
      }
    }
    expect(
      rows,
      containsPair('sendTypingNotifications', anything),
      reason: 'the scan reads files that are not named *_view.dart',
    );
    final duplicated = {
      for (final entry in rows.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };
    expect(duplicated, isEmpty);
  });

  test('chat settings does not carry the emotes entry', () {
    final source = File(
      'lib/pages/settings_chat/settings_chat_view.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('customEmojisAndStickers')));
    expect(source, isNot(contains('/emotes')));
  });
}
