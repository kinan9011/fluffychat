// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _directories = [
  'lib/utils/search',
  'lib/pages/global_search',
  'lib/utils/spaces',
  'lib/pages/space_overview',
  'lib/utils/links',
  'lib/utils/new_message',
  'lib/pages/new_private_chat',
];

/// The index and everything around search holds plaintext of encrypted rooms
/// and the user's queries: it may only touch the encrypted database through
/// the SDK, must not write files or preferences, must not log content and
/// must not do anything other people could notice (receipts, typing, presence).
const _forbidden = [
  'SharedPreferences',
  'AppSettings.store',
  'dart:io',
  'File(',
  'path_provider',
  'debugPrint(',
  'print(',
  'setReadMarker',
  'markUnread',
  'setTyping',
  'postReceipt',
  'setPresence',
  'sendReadMarker',
  'sendTypingNotification',
  'fetchCurrentPresence',
  'launchUrl',
  'launchUrlString',
];

List<File> _sources() => [
  for (final directory in _directories)
    if (Directory(directory).existsSync())
      ...Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
];

/// The purge of the old preferences is the one place that has to read them.
bool isLegacyPurge(File file) =>
    file.path.endsWith('utils/spaces/legacy_cache_purge.dart');

/// The QR scanner picks the camera permission by operating system.
bool isScannerModal(File file) =>
    file.path.endsWith('new_private_chat/qr_scanner_modal.dart');

String _code(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('the search code exists', () {
    expect(_sources(), isNotEmpty);
  });

  for (final file in _sources()) {
    test('${file.path} touches nothing outside the encrypted database', () {
      final source = _code(file);
      for (final identifier in _forbidden) {
        if (isLegacyPurge(file) && identifier == 'SharedPreferences') continue;
        if (isScannerModal(file) && identifier == 'dart:io') continue;
        expect(source, isNot(contains(identifier)), reason: identifier);
      }
    });

    test('${file.path} stores nothing but the directory server name', () {
      final lines = _code(file).split('\n');
      for (final line in lines.where((l) => l.contains('.store.'))) {
        expect(line, contains('serverStoreKey'), reason: line);
      }
      expect(
        RegExp(r'\.store\.set\w+\((?!serverStoreKey)').hasMatch(_code(file)),
        isFalse,
      );
    });

    test('${file.path} logs constant strings only', () {
      final source = _code(file);
      final calls = RegExp(r'Logs\(\)\.\w+\(([^;]*)\)', dotAll: true);
      for (final match in calls.allMatches(source)) {
        final arguments = match.group(1)!;
        expect(
          arguments,
          matches(RegExp(r"^\s*'[^'$]*',?\s*$")),
          reason: match.group(0),
        );
      }
    });
  }

  test('the scanner modal uses dart:io for Platform only', () {
    final source = _code(
      File('lib/pages/new_private_chat/qr_scanner_modal.dart'),
    );
    expect(source, contains('dart:io'));
    expect(source, isNot(contains('File(')));
    expect(source, isNot(contains('Directory(')));
    expect(source, isNot(contains('Process.')));
    expect(source, isNot(contains('Socket')));
  });

  test('the legacy purge only uses nothing but getKeys and remove', () {
    final source = _code(File('lib/utils/spaces/legacy_cache_purge.dart'));
    final calls = RegExp(r'store\s*\.\s*(\w+)').allMatches(source);
    expect({for (final match in calls) match.group(1)}, {'getKeys', 'remove'});
  });
}
