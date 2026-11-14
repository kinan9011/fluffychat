// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the launch wrappers import package:url_launcher', () {
    final pattern = RegExp(
      r'''^\s*(import|export)\s+['"]package:url_launcher''',
      multiLine: true,
    );
    final importers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => pattern.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toSet();
    expect(importers, {
      'lib/utils/url_launcher.dart',
      'lib/utils/launch_web_url.dart',
    });
  });
}
