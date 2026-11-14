// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/utils/backup_dump_validator.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> validDump() => {
  for (final box in requiredBackupBoxes) box: <String, Object?>{},
  'box_client': {'user_id': 'fake'},
};

Uint8List encode(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

void expectInvalid(Uint8List bytes, {bool tooLarge = false}) {
  expect(
    () => validateBackupDump(bytes),
    throwsA(
      isA<InvalidBackupException>().having(
        (e) => e.tooLarge,
        'tooLarge',
        tooLarge,
      ),
    ),
  );
}

void main() {
  test('a backup is capped at 64 MiB', () {
    expect(maxBackupDumpBytes, 64 * 1024 * 1024);
  });

  group('validateBackupDump', () {
    test('accepts a complete dump and returns the decoded text', () {
      final dump = validDump();
      expect(validateBackupDump(encode(dump)), jsonEncode(dump));
    });

    test('decodes UTF-8, not latin1', () {
      final dump = validDump()..['box_rooms'] = {'r': 'Grüße 🎉 مرحبا'};
      expect(validateBackupDump(encode(dump)), contains('Grüße 🎉 مرحبا'));
    });

    test('accepts additional box_ entries', () {
      expect(
        () =>
            validateBackupDump(encode(validDump()..['box_events'] = {'e': {}})),
        returnsNormally,
      );
    });

    test('rejects dumps above the size cap', () {
      expect(
        () => validateBackupDump(encode(validDump()), maxBytes: 10),
        throwsA(
          isA<InvalidBackupException>().having(
            (e) => e.tooLarge,
            'tooLarge',
            isTrue,
          ),
        ),
      );
    });

    test('rejects non UTF-8 bytes', () {
      expectInvalid(Uint8List.fromList([0xff, 0xfe, 0x00, 0x80]));
    });

    test('rejects non JSON', () {
      expectInvalid(Uint8List.fromList(utf8.encode('not json')));
    });

    test('rejects JSON that is not an object', () {
      expectInvalid(encode([1, 2, 3]));
      expectInvalid(encode('string'));
      expectInvalid(encode(null));
    });

    test('rejects an empty object', () {
      expectInvalid(encode(<String, Object?>{}));
    });

    test('rejects a missing required box', () {
      for (final box in requiredBackupBoxes) {
        expectInvalid(encode(validDump()..remove(box)));
      }
    });

    test('rejects a box that is not an object', () {
      expectInvalid(encode(validDump()..['box_rooms'] = [1]));
      expectInvalid(encode(validDump()..['box_rooms'] = 'x'));
      expectInvalid(encode(validDump()..['box_rooms'] = null));
    });

    test('rejects an empty client box', () {
      expectInvalid(encode(validDump()..['box_client'] = <String, Object?>{}));
    });

    test('rejects unexpected top level keys', () {
      expectInvalid(encode(validDump()..['evil'] = {}));
    });
  });
}
