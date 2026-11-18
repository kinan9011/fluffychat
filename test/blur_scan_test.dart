// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only files that may blur what is behind them. Every one of them asks
/// `glassIsSolid` (or is a user chosen wallpaper blur on one image).
const _blurFiles = {
  'lib/widgets/glass_surface.dart',
  'lib/pages/chat/scheduling/send_options_menu.dart',
  'lib/pages/chat_list/peek_sheet.dart',
  'lib/pages/chat/chat_wallpaper.dart',
};

void main() {
  test('BackdropFilter and blur filters live only in the allowed files', () {
    final blur = RegExp(r'BackdropFilter|ImageFilter\.blur|ImageFiltered');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_blurFiles.contains(entity.path)) continue;
      if (blur.hasMatch(entity.readAsStringSync())) offenders.add(entity.path);
    }
    expect(offenders, isEmpty);
  });

  test('the scrim blurs of the menus ask the glass policy', () {
    for (final path in [
      'lib/pages/chat/scheduling/send_options_menu.dart',
      'lib/pages/chat_list/peek_sheet.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('glassIsSolidNow('),
        reason: path,
      );
    }
  });

  test('a list row never builds a blurring glass surface', () {
    final offenders = <String>[];
    final glass = RegExp(r'GlassSurface\(');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final match in RegExp(r'itemBuilder:').allMatches(text)) {
        final window = text.substring(
          match.end,
          match.end + 1500 > text.length ? text.length : match.end + 1500,
        );
        for (final g in glass.allMatches(window)) {
          final call = window.substring(
            g.start,
            window.indexOf(');', g.start) == -1
                ? window.length
                : window.indexOf(');', g.start),
          );
          if (!call.contains('solid: true')) {
            offenders.add(entity.path);
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('scheduled message rows are solid', () {
    final text = File(
      'lib/pages/chat/scheduling/scheduled_messages_view.dart',
    ).readAsStringSync();
    final entry = text.substring(text.indexOf('class _Entry'));
    for (final m in RegExp(r'GlassSurface\(').allMatches(entry)) {
      final end = entry.indexOf(')', m.end);
      expect(
        entry.substring(
          m.start,
          end + 200 > entry.length ? entry.length : end + 200,
        ),
        contains('solid: true'),
      );
    }
  });
}
