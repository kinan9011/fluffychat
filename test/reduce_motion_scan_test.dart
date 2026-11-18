// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Not animations of widgets: the value is used for a scroll, a page change or
/// a delay, which the platform handles or which has no visible motion.
const _allowed = {
  'lib/config/themes.dart',
  'lib/pages/chat/chat.dart',
  'lib/pages/image_viewer/image_viewer.dart',
  'lib/utils/motion.dart',
};

void main() {
  test(
    'every widget animation uses motionDuration (reduce motion, DESIGN 13)',
    () {
      final pattern = RegExp(r'FluffyThemes\s*\.\s*animationDuration');
      final wrapped = RegExp(r'motionDuration\(\s*[A-Za-z_.]+,\s*$');
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (_allowed.contains(entity.path)) continue;
        final text = entity.readAsStringSync();
        for (final match in pattern.allMatches(text)) {
          final before = text.substring(
            match.start < 200 ? 0 : match.start - 200,
            match.start,
          );
          if (wrapped.hasMatch(before)) continue;
          if (RegExp(r'this\.animationDuration\s*=\s*$').hasMatch(before)) {
            continue;
          }
          final line =
              '\n'.allMatches(text.substring(0, match.start)).length + 1;
          offenders.add('${entity.path}:$line');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'wrap the duration in motionDuration(context, ...) or add the file '
            'to the allowlist with a reason',
      );
    },
  );

  test('a directly written Duration in an implicit animation is refused', () {
    final animated = RegExp(
      r'Animated(Size|Container|Scale|Opacity|Switcher|CrossFade|Align|'
      r'Positioned|Padding|Slide|Rotation|DefaultTextStyle)\(',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final match in animated.allMatches(text)) {
        final end = text.indexOf('child:', match.end);
        final window = text.substring(
          match.end,
          end == -1 || end - match.end > 400 ? match.end + 400 : end,
        );
        final literal = RegExp(r'duration:\s*(const\s+)?Duration\(');
        if (literal.hasMatch(window)) {
          final line =
              '\n'.allMatches(text.substring(0, match.start)).length + 1;
          offenders.add('${entity.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
