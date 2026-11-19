// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  List<File> dart(String directory) => [
    for (final entity in Directory(directory).listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  final files = [
    ...dart('lib/utils/scheduling'),
    ...dart('lib/pages/chat/scheduling'),
  ];

  String code(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the guard sees every file', () {
    expect(files.length, greaterThanOrEqualTo(15));
  });

  test('scheduled text never goes to preferences, files or the console', () {
    for (final file in files) {
      for (final identifier in [
        'SharedPreferences',
        'AppSettings',
        'FlutterSecureStorage',
        'File(',
        'print(',
        'debugPrint(',
      ]) {
        final menu = file.path.endsWith('send_options_menu.dart');
        if (menu && identifier == 'AppSettings') continue;
        expect(
          code(file),
          isNot(contains(identifier)),
          reason: '${file.path} uses $identifier',
        );
      }
    }
  });

  test('a log line carries constant text and the type of an error only', () {
    for (final file in files) {
      for (final line in code(file).split('\n')) {
        if (!line.contains('Logs()')) continue;
        final rest = line.replaceAll(r'${e.runtimeType}', '');
        expect(rest, isNot(contains(r'$')), reason: '${file.path}: $line');
      }
    }
  });

  test('server copies are never decrypted, the SDK list is never used', () {
    for (final file in files) {
      for (final identifier in [
        'decryptRoomEvent',
        'decryptRoomEventSync',
        'getScheduledDelayedEvents',
        'ScheduledDelayedEvent',
      ]) {
        expect(
          code(file),
          isNot(contains(identifier)),
          reason: '${file.path} uses $identifier',
        );
      }
    }
  });

  test('no request leaves for anything but the homeserver', () {
    for (final file in files) {
      for (final identifier in [
        'package:http',
        'HttpClient',
        "Uri.parse('http",
        'launchUrl',
        'UrlLauncher',
        'dart:io',
      ]) {
        expect(
          code(file),
          isNot(contains(identifier)),
          reason: '${file.path} uses $identifier',
        );
      }
    }
  });

  test('only the app UI library and no SDK internals', () {
    for (final file in dart('lib')) {
      expect(
        code(file),
        isNot(contains('package:matrix/src/')),
        reason: '${file.path} imports SDK internals',
      );
    }
    for (final file in files) {
      expect(
        code(file),
        isNot(contains('package:flutter/material.dart')),
        reason: file.path,
      );
    }
  });

  test('every file carries the licence header', () {
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        contains(
          'SPDX-License-'
          'Identifier: AGPL-3.0-or-later',
        ),
        reason: file.path,
      );
    }
  });

  test('the silent flag is written in one place only', () {
    final writers = [
      for (final file in dart('lib'))
        if (code(file).contains('com.swovo.odango.silent')) file.path,
    ];
    expect(writers, ['lib/utils/scheduling/scheduled_content.dart']);
  });

  test('both notification paths ask the helper with the highlight', () {
    for (final path in [
      'lib/utils/push_helper.dart',
      'lib/widgets/local_notifications_extension.dart',
    ]) {
      final text = code(File(path));
      expect(text, contains('notifySilently('), reason: path);
      expect(text, contains('highlight:'), reason: path);
    }
  });
}
