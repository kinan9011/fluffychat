// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_quarantine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('db_quarantine_test');
    path = '${dir.path}/a.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  List<String> names() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('renames the database and its side files, keeping every byte', () async {
    final main = List.generate(500, (i) => i % 251);
    write('a.sqlite', main);
    write('a.sqlite-wal', [1, 2, 3]);
    write('a.sqlite-shm', [4, 5]);
    write('a.sqlite-journal', [6]);

    await quarantineDatabase(path);

    expect(names(), [
      'a.sqlite.quarantine-1',
      'a.sqlite.quarantine-1-journal',
      'a.sqlite.quarantine-1-shm',
      'a.sqlite.quarantine-1-wal',
    ]);
    expect(File('${dir.path}/a.sqlite.quarantine-1').readAsBytesSync(), main);
    expect(File('${dir.path}/a.sqlite.quarantine-1-wal').readAsBytesSync(), [
      1,
      2,
      3,
    ]);
  });

  test('a missing database is a no-op', () async {
    await quarantineDatabase(path);
    expect(names(), isEmpty);
  });

  test('copies are numbered by sequence, not by time', () async {
    for (var i = 1; i <= 3; i++) {
      write('a.sqlite', [i]);
      await quarantineDatabase(path);
    }

    expect(names(), ['a.sqlite.quarantine-2', 'a.sqlite.quarantine-3']);
    expect(File('${dir.path}/a.sqlite.quarantine-3').readAsBytesSync(), [3]);
  });

  test('keeps the two highest sequence numbers, also with gaps', () async {
    write('a.sqlite.quarantine-1', [1]);
    write('a.sqlite.quarantine-1-wal', [1]);
    write('a.sqlite.quarantine-5', [5]);
    write('a.sqlite.quarantine-9', [9]);
    write('a.sqlite', [10]);

    await quarantineDatabase(path);

    expect(names(), ['a.sqlite.quarantine-10', 'a.sqlite.quarantine-9']);
    expect(File('${dir.path}/a.sqlite.quarantine-10').readAsBytesSync(), [10]);
  });

  test('the new copy is never the one that is pruned', () async {
    write('a.sqlite.quarantine-1700000000', [1]);
    write('a.sqlite.quarantine-1700000001', [2]);
    write('a.sqlite', [3]);

    await quarantineDatabase(path);

    expect(
      File('${dir.path}/a.sqlite.quarantine-1700000002').readAsBytesSync(),
      [3],
    );
    expect(names(), [
      'a.sqlite.quarantine-1700000001',
      'a.sqlite.quarantine-1700000002',
    ]);
  });

  test('copies of other databases are never pruned', () async {
    write('b.sqlite.quarantine-1', [1]);
    write('b.sqlite.quarantine-2', [1]);
    write('b.sqlite.quarantine-3', [1]);
    write('a.sqlite', [9]);

    await quarantineDatabase(path);

    expect(names(), [
      'a.sqlite.quarantine-1',
      'b.sqlite.quarantine-1',
      'b.sqlite.quarantine-2',
      'b.sqlite.quarantine-3',
    ]);
  });

  test('a failing rename throws and deletes nothing', () async {
    write('a.sqlite', [1]);
    write('a.sqlite-wal', [2]);

    await expectLater(
      quarantineDatabase(
        path,
        rename: (file, newPath) async => throw const FileSystemException('x'),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(names(), ['a.sqlite', 'a.sqlite-wal']);
    expect(File('${dir.path}/a.sqlite').readAsBytesSync(), [1]);
  });

  test('a stale side file is removed when only its rename fails', () async {
    write('a.sqlite', [1]);
    write('a.sqlite-wal', [2]);

    await quarantineDatabase(
      path,
      rename: (file, newPath) async {
        if (file.path.endsWith('-wal')) throw const FileSystemException('x');
        await file.rename(newPath);
      },
    );

    expect(names(), ['a.sqlite.quarantine-1']);
  });

  group('deleteQuarantinedDatabases', () {
    test('removes every copy of the database with its side files', () async {
      write('a.sqlite.quarantine-1', [1]);
      write('a.sqlite.quarantine-1-wal', [1]);
      write('a.sqlite.quarantine-2', [1]);
      write('b.sqlite.quarantine-1', [1]);
      write('a.sqlite', [1]);
      write('a.sqlite.quarantine-x', [1]);

      await deleteQuarantinedDatabases(path);

      expect(names(), [
        'a.sqlite',
        'a.sqlite.quarantine-x',
        'b.sqlite.quarantine-1',
      ]);
    });
  });
}
