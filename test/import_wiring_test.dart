// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/archive_guard.dart';
import 'package:fluffychat/utils/backup_dump_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFile extends XFile {
  final int fakeLength;
  final Uint8List bytes;
  int reads = 0;

  _FakeFile(this.bytes, {int? length})
    : fakeLength = length ?? bytes.length,
      super('fake');

  @override
  Future<int> length() async => fakeLength;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return bytes;
  }
}

Uint8List zipOf(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List validBackup() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      for (final box in requiredBackupBoxes) box: <String, Object?>{},
      'box_client': {'user_id': 'fake'},
    }),
  ),
);

void main() {
  group('backup import runs the validator before importing', () {
    test('a valid backup is handed to the importer as decoded text', () async {
      String? imported;
      final result = await importBackupFile(_FakeFile(validBackup()), (
        dump,
      ) async {
        imported = dump;
        return 42;
      });
      expect(result, 42);
      expect(imported, utf8.decode(validBackup()));
    });

    test('an invalid backup never reaches the importer', () async {
      var called = false;
      await expectLater(
        importBackupFile(_FakeFile(Uint8List.fromList(utf8.encode('{}'))), (
          dump,
        ) async {
          called = true;
        }),
        throwsA(isA<InvalidBackupException>()),
      );
      expect(called, isFalse);
    });

    test('an oversized file is rejected before it is read', () async {
      final file = _FakeFile(Uint8List(0), length: maxBackupDumpBytes + 1);
      var called = false;
      await expectLater(
        importBackupFile(file, (dump) async {
          called = true;
        }),
        throwsA(
          isA<InvalidBackupException>().having(
            (e) => e.tooLarge,
            'tooLarge',
            isTrue,
          ),
        ),
      );
      expect(file.reads, 0);
      expect(called, isFalse);
    });
  });

  group('archive file import', () {
    test('extracts a valid archive', () async {
      final entries = await readArchiveFile(
        _FakeFile(
          zipOf({
            'a.png': [1, 2, 3],
          }),
        ),
      );
      expect(entries.single.name, 'a.png');
    });

    test('an oversized file is rejected before it is read', () async {
      final file = _FakeFile(
        Uint8List(0),
        length: ArchiveLimits.emotes.maxArchiveBytes + 1,
      );
      await expectLater(
        readArchiveFile(file),
        throwsA(
          isA<ArchiveGuardException>().having(
            (e) => e.error,
            'error',
            ArchiveGuardError.tooLarge,
          ),
        ),
      );
      expect(file.reads, 0);
    });

    test('a traversal archive is rejected', () async {
      await expectLater(
        readArchiveFile(
          _FakeFile(
            zipOf({
              '../evil.png': [1],
            }),
          ),
        ),
        throwsA(
          isA<ArchiveGuardException>().having(
            (e) => e.error,
            'error',
            ArchiveGuardError.unsafePaths,
          ),
        ),
      );
    });
  });

  group('platform configuration wiring', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
    });

    tearDown(() => AppSettings.applyPlatformConfiguration(null, .web));

    test('web config.json is filtered before it becomes a default', () {
      final gateway = AppSettings.pushNotificationsGatewayUrl.defaultValue;

      AppSettings.applyPlatformConfiguration({
        'applicationName': 'Acme',
        'pushNotificationsGatewayUrl': 'https://evil.example/notify',
        'sendPublicReadReceipts': true,
        'sendTypingNotifications': false,
      }, PlatformConfigSource.web);

      expect(AppSettings.applicationName.defaultValue, 'Acme');
      expect(AppSettings.pushNotificationsGatewayUrl.defaultValue, gateway);
      expect(AppSettings.sendTypingNotifications.defaultValue, isFalse);
    });

    test('MDM configuration keeps admin push settings', () {
      AppSettings.applyPlatformConfiguration({
        'pushNotificationsGatewayUrl': 'https://push.corp.example/notify',
        'unifiedPushEndpoint': 'https://evil.example',
      }, PlatformConfigSource.mdm);

      expect(
        AppSettings.pushNotificationsGatewayUrl.defaultValue,
        'https://push.corp.example/notify',
      );
      expect(AppSettings.unifiedPushEndpoint.defaultValue, isEmpty);
    });
  });
}
