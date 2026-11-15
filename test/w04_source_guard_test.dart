// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guards over every file the conversation shell and the message
/// bubbles added. They are syntactic on purpose: they catch the day somebody
/// reaches for trust, storage or logging from a view.
void main() {
  final files = [
    for (final path in [
      'lib/pages/chat/chat_header.dart',
      'lib/pages/chat/chat_jump_buttons.dart',
      'lib/pages/chat/chat_overflow_menu.dart',
      'lib/pages/chat/chat_wallpaper.dart',
      'lib/pages/chat/mention_suggestion_tile.dart',
      'lib/pages/chat/message_action_runner.dart',
      'lib/pages/chat/message_menu.dart',
      'lib/pages/chat/new_device_banner.dart',
      'lib/pages/chat/seen_by_row.dart',
      'lib/pages/chat/utd_why_sheet.dart',
      'lib/pages/chat/events/custom_reaction_sheet.dart',
      'lib/pages/chat/events/deleted_bubble_content.dart',
      'lib/pages/chat/events/file_bubble_view.dart',
      'lib/pages/chat/events/message_bubble.dart',
      'lib/pages/chat/events/message_focus.dart',
      'lib/pages/chat/events/message_footer.dart',
      'lib/pages/chat/events/message_hover_actions.dart',
      'lib/pages/chat/events/reaction_bar.dart',
      'lib/pages/chat/events/reaction_pills.dart',
      'lib/pages/chat/events/utd_bubble_content.dart',
      'lib/pages/chat/events/voice_bubble_view.dart',
      'lib/widgets/glass_menu.dart',
    ])
      File(path),
    for (final entity in Directory('lib/utils/chat').listSync())
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  String code(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the guard sees every file', () {
    expect(files.length, greaterThan(25));
    for (final file in files) {
      expect(file.existsSync(), isTrue, reason: file.path);
    }
  });

  test('no view of the conversation shell decides about trust', () {
    for (final file in files) {
      for (final identifier in [
        'setVerified',
        'setBlocked',
        'startVerification',
        'crossSigning',
        'openSSSS',
        'bootstrap',
      ]) {
        expect(
          code(file),
          isNot(contains(identifier)),
          reason: '${file.path} uses $identifier',
        );
      }
    }
  });

  test('no view of the conversation shell stores or logs content', () {
    for (final file in files) {
      for (final identifier in [
        'SharedPreferences',
        '.setItem(',
        'FlutterSecureStorage',
        'File(',
        'print(',
      ]) {
        if (file.path.endsWith('w04_source_guard_test.dart')) continue;
        expect(
          code(file),
          isNot(contains(identifier)),
          reason: '${file.path} uses $identifier',
        );
      }
      final logs = RegExp(r'Logs\(\)\.\w+\((.*)\)').allMatches(code(file));
      for (final match in logs) {
        expect(
          match.group(1),
          matches(RegExp(r"^'[^'$]*'")),
          reason: '${file.path} logs something that is not a constant',
        );
      }
    }
  });
}
