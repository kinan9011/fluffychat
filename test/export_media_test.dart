// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/export/export_media.dart';
import 'package:odango/utils/export/export_model.dart';

void main() {
  group('safeMediaName', () {
    final hostile = [
      '../../etc/passwd',
      r'a/b\c',
      '..',
      '...',
      '.hidden',
      '/absolute',
      r'C:\Windows\system32',
      'CON',
      'file\u0000name.png',
      'emoji 😀.png',
      '  ',
      '',
      'a' * 500,
    ];

    for (final raw in hostile) {
      test(
        'stays inside media/: "${raw.length > 30 ? '${raw.substring(0, 30)}…' : raw}"',
        () {
          final name = safeMediaName(7, raw);
          expect(name, startsWith('000007-'));
          expect(name, isNot(contains('/')));
          expect(name, isNot(contains(r'\')));
          expect(name, isNot(contains('..')));
          expect(name, isNot(contains('\u0000')));
          expect(name.length, lessThanOrEqualTo(7 + 80));
          expect(RegExp(r'^[A-Za-z0-9._ -]+$').hasMatch(name), isTrue);
          expect(name.substring(7).startsWith('.'), isFalse);
        },
      );
    }

    test('an extension that runs scripts when opened is not kept (B-4)', () {
      for (final raw in [
        'evil.html',
        'EVIL.HTM',
        'x.xhtml',
        'pic.svg',
        'pic.svgz',
        'a.xml',
        'a.js',
        'a.mjs',
        'a.hta',
        'a.mht',
        'a.mhtml',
        'a.html.png.html',
        'invite.html.',
        'invite.html . .',
      ]) {
        final name = safeMediaName(3, raw);
        final extension = name.split('.').last.toLowerCase();
        expect(
          {
            'html',
            'htm',
            'xhtml',
            'svg',
            'svgz',
            'xml',
            'js',
            'mjs',
            'hta',
            'mht',
            'mhtml',
          },
          isNot(contains(extension)),
          reason: raw,
        );
        expect(name, startsWith('000003-'));
        expect(name, endsWith('.bin'), reason: raw);
        expect(name, isNot(matches(RegExp(r'[.\s]$'))), reason: raw);
      }
      expect(safeMediaName(3, 'photo.png'), '000003-photo.png');
      expect(safeMediaName(3, 'doc.pdf'), '000003-doc.pdf');
    });

    test('different indexes give different names for the same file', () {
      expect(safeMediaName(1, 'a.png'), isNot(safeMediaName(2, 'a.png')));
    });

    test('a normal name stays readable', () {
      expect(
        safeMediaName(12, 'holiday photo.jpg'),
        '000012-holiday photo.jpg',
      );
    });
  });

  group('MediaBudget', () {
    test('a file above the per file cap is refused', () {
      final budget = MediaBudget();
      expect(budget.take(ExportLimits.maxMediaPerFile + 1), isFalse);
      expect(budget.take(ExportLimits.maxMediaPerFile), isTrue);
    });

    test('the total cap ends the allowance', () {
      final budget = MediaBudget();
      var taken = 0;
      while (budget.take(ExportLimits.maxMediaPerFile)) {
        taken++;
      }
      expect(taken, ExportLimits.maxMediaTotal ~/ ExportLimits.maxMediaPerFile);
      expect(budget.used, lessThanOrEqualTo(ExportLimits.maxMediaTotal));
    });

    test('a negative size is refused', () {
      expect(MediaBudget().take(-1), isFalse);
      expect(MediaBudget().couldFit(-5), isFalse);
    });

    test('couldFit does not spend', () {
      final budget = MediaBudget();
      expect(budget.couldFit(1000), isTrue);
      expect(budget.used, 0);
    });
  });
}
