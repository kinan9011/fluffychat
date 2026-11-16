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
    ...dart('lib/utils/rich_text'),
    ...dart('lib/pages/chat/composer'),
    File('lib/utils/draft_store.dart'),
    File('lib/utils/draft_migration.dart'),
    File('lib/utils/html_limits.dart'),
  ];

  String code(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the guard sees every file', () {
    expect(files.length, greaterThan(15));
  });

  test('no file stores or logs content', () {
    for (final file in files) {
      for (final identifier in [
        'SharedPreferences',
        'FlutterSecureStorage',
        'File(',
        'print(',
        'debugPrint(',
      ]) {
        if (file.path.endsWith('draft_migration.dart') &&
            identifier == 'SharedPreferences') {
          continue;
        }
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
          matches(RegExp(r"^'[^'$]*'$")),
          reason: '${file.path} logs more than a constant string',
        );
      }
    }
  });

  test('no draft preference is written anywhere in lib', () {
    for (final file in dart('lib')) {
      final source = code(file);
      if (file.path.endsWith('draft_migration.dart')) continue;
      expect(
        source,
        isNot(contains("'draft_")),
        reason: '${file.path} touches the old draft preference key',
      );
    }
    final migration = code(File('lib/utils/draft_migration.dart'));
    expect(migration, contains("_legacyPrefix = 'draft_'"));
    expect(migration, isNot(contains('setString')));
    expect(migration, isNot(contains('setInt')));
  });

  test('drafts follow the account of the page, not the sending account', () {
    final chat = code(File('lib/pages/chat/chat.dart'));
    expect(chat, isNot(contains('DraftStore.of(sendingClient')));
    expect(chat, isNot(contains('DraftStore.of(c)')));
    expect(chat, contains('DraftStore.of(widget.room.client)'));
    expect(chat, isNot(contains('DraftStore.of(Matrix.of(context)')));
  });

  test('the serializer is the only producer of message html', () {
    for (final file
        in dart('lib/pages/chat/composer') + dart('lib/utils/rich_text')) {
      if (file.path.endsWith('html_serializer.dart')) continue;
      final source = code(file);
      for (final tag in ['<strong>', '<em>', '<a href', '<span data-mx']) {
        expect(
          source,
          isNot(contains(tag)),
          reason: '${file.path} builds html outside the serializer',
        );
      }
    }
  });

  test('only send_rich_message sends events from the composer code', () {
    for (final file in files) {
      if (file.path.endsWith('send_rich_message.dart')) continue;
      expect(
        code(file),
        isNot(contains('.sendEvent(')),
        reason: '${file.path} sends an event',
      );
    }
  });

  test('the composer code never decides about trust or hands out raw html', () {
    for (final file in files) {
      for (final identifier in [
        'setVerified',
        'setBlocked',
        'startVerification',
        'markdownToHtml',
        'HtmlUnescape',
        'innerHtml',
        'outerHtml',
      ]) {
        expect(
          code(file),
          isNot(contains(identifier)),
          reason: '${file.path} uses $identifier',
        );
      }
    }
  });

  test('no flutter material import and no colour literal in new files', () {
    for (final file in files) {
      final source = code(file);
      expect(
        source,
        isNot(contains('package:flutter/material.dart')),
        reason: file.path,
      );
      expect(source, isNot(contains('Colors.')), reason: file.path);
      expect(
        RegExp(r'Color\(0x[0-9a-fA-F]+\)').hasMatch(source),
        isFalse,
        reason: file.path,
      );
    }
  });
}
