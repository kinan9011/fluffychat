// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_file_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('db_state_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File fileWith(List<int> bytes) =>
      File('${dir.path}/x.sqlite')..writeAsBytesSync(bytes);

  final header = [...'SQLite format 3'.codeUnits, 0];

  test('a missing file is no database', () async {
    expect(
      await databaseFileState(File('${dir.path}/missing.sqlite')),
      DatabaseFileState.none,
    );
  });

  test('an empty file is no database', () async {
    expect(await databaseFileState(fileWith([])), DatabaseFileState.none);
  });

  test('the sqlite header marks a plaintext database', () async {
    expect(
      await databaseFileState(fileWith([...header, ...List.filled(100, 7)])),
      DatabaseFileState.plaintext,
    );
  });

  test('a file with only the header bytes is plaintext', () async {
    expect(
      await databaseFileState(fileWith(header)),
      DatabaseFileState.plaintext,
    );
  });

  test('random bytes look like an encrypted database', () async {
    final random = Random(1);
    final bytes = Uint8List.fromList(
      List.generate(4096, (_) => random.nextInt(256)),
    );
    expect(
      await databaseFileState(fileWith(bytes)),
      DatabaseFileState.encrypted,
    );
  });

  test('the header without the NUL byte is not plaintext', () async {
    expect(
      await databaseFileState(
        fileWith([...'SQLite format 3'.codeUnits, 1, ...List.filled(50, 0)]),
      ),
      DatabaseFileState.encrypted,
    );
  });

  test('a short non-empty file is not trusted as plaintext', () async {
    expect(
      await databaseFileState(fileWith('SQLite'.codeUnits)),
      DatabaseFileState.encrypted,
    );
  });

  test('an unreadable file counts as encrypted', () async {
    final file = fileWith([...header, 1, 2, 3]);
    Process.runSync('chmod', ['000', file.path]);
    addTearDown(() => Process.runSync('chmod', ['600', file.path]));

    expect(await databaseFileState(file), DatabaseFileState.encrypted);
  }, skip: Platform.isWindows);
}
