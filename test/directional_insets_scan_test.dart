// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Places where a physical side is meant, with the reason. Everything else in
/// `lib/pages` and `lib/widgets` places its content with start and end, so
/// right to left languages mirror (DESIGN 13).
const _allowed = <String, String>{
  'lib/pages/chat/message_menu.dart':
      'places the menu at physical coordinates that MenuPlacement already '
      'computes for the text direction (menu_placement_test, RTL cases)',
  'lib/pages/chat/chat_overflow_menu.dart':
      'places the menu at coordinates computed for the text direction',
  'lib/pages/chat/scheduling/send_options_menu.dart':
      'places the menu at coordinates computed for the text direction',
  'lib/pages/chat/events/cute_events.dart':
      'confetti and hearts fly over the screen in screen space, not text flow',
};

/// Each rule: a regular expression over one source file (matches may span
/// lines, so a multi-line call is found) and a name for the report.
final _rules = <String, RegExp>{
  'EdgeInsets.only(left/right)': RegExp(
    r'EdgeInsets\.only\((?:[^()]|\([^()]*\))*?\b(?:left|right):',
  ),
  'EdgeInsets.fromLTRB': RegExp(r'EdgeInsets\.fromLTRB\('),
  'Positioned(left/right)': RegExp(
    r'\bPositioned\((?:[^()]|\([^()]*\))*?\b(?:left|right):',
  ),
  'Alignment.<side>': RegExp(
    r'\bAlignment\.(?:centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b',
  ),
  'TextAlign.left/right': RegExp(r'\bTextAlign\.(?:left|right)\b'),
};

void main() {
  test('every page and widget places its content with start and end', () {
    final offenders = <String>[];
    for (final root in ['lib/pages', 'lib/widgets']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        for (final rule in _rules.entries) {
          for (final match in rule.value.allMatches(text)) {
            final line =
                '\n'.allMatches(text.substring(0, match.start)).length + 1;
            if (_allowed.containsKey(entity.path)) continue;
            offenders.add('${entity.path}:$line  ${rule.key}');
          }
        }
      }
    }
    expect(offenders.join('\n'), isEmpty);
  });

  test('every allowed exception carries a reason', () {
    for (final reason in _allowed.values) {
      expect(reason.trim().length, greaterThan(15));
    }
  });
}
