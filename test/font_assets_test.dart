// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fluffychat/utils/font_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pinned = <String, String>{
    for (final match in RegExp(
      r'^\| (\S+\.(?:ttf|txt)) \|.*\| ([0-9a-f]{64}) \|$',
      multiLine: true,
    ).allMatches(File('assets/fonts/SOURCES.md').readAsStringSync()))
      match.group(1)!: match.group(2)!,
  };

  test('SOURCES.md pins every bundled font and licence text', () {
    final files = Directory('assets/fonts')
        .listSync()
        .map((entity) => entity.uri.pathSegments.last)
        .where((name) => name != 'SOURCES.md')
        .toSet();
    expect(files, isNotEmpty);
    expect(pinned.keys.toSet(), files);
  });

  test('bundled files match the pinned upstream sha256', () {
    for (final entry in pinned.entries) {
      final bytes = File('assets/fonts/${entry.key}').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), entry.value, reason: entry.key);
    }
  });

  test('every font declared in pubspec.yaml is a pinned file', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'asset: assets/fonts/(\S+)',
    ).allMatches(pubspec).map((match) => match.group(1)!).toList();
    expect(declared, hasLength(6));
    expect(pinned.keys, containsAll(declared));
    expect(pubspec, contains('family: Figtree'));
    expect(pubspec, contains('family: JetBrainsMono'));
  });

  test('licences are present and REUSE annotates the fonts as OFL-1.1', () {
    expect(
      File('LICENSES/OFL-1.1.txt').readAsStringSync(),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );
    final blocks = File(
      'REUSE.toml',
    ).readAsStringSync().split('[[annotations]]');
    for (final glob in [
      'assets/fonts/Figtree-*',
      'assets/fonts/JetBrainsMono-*',
    ]) {
      final block = blocks.singleWhere((block) => block.contains('"$glob"'));
      expect(
        block,
        contains('SPDX-License-Identifier = "OFL-1.1"'),
        reason: glob,
      );
      expect(block, contains('Project Authors'), reason: glob);
    }
    for (final file in ['Figtree-OFL.txt', 'JetBrainsMono-OFL.txt']) {
      expect(
        File('assets/fonts/$file').readAsStringSync(),
        contains('SIL Open Font License, Version 1.1'),
      );
    }
  });

  testWidgets('the OFL notices are bundled and shown on the licence page', (
    tester,
  ) async {
    registerFontLicenses();
    final text = await LicenseRegistry.licenses
        .map(
          (entry) =>
              '${entry.packages.join()} ${entry.paragraphs.map((p) => p.text).join()}',
        )
        .toList();
    expect(
      text.any(
        (t) => t.contains('Figtree') && t.contains('Figtree Project Authors'),
      ),
      isTrue,
    );
    expect(
      text.any(
        (t) =>
            t.contains('JetBrains Mono') &&
            t.contains('JetBrains Mono Project Authors'),
      ),
      isTrue,
    );
  });
}
