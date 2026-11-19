// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/shared_media_filter.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

const _u1 = '11111111-1111-4111-8111-111111111111';
const _u2 = '22222222-2222-4222-8222-222222222222';
const _u3 = '33333333-3333-4333-8333-333333333333';
const _u4 = '44444444-4444-4444-8444-444444444444';

List<String> _tree(Directory dir) =>
    dir
        .listSync(recursive: true, followLinks: false)
        .map((e) => e.path)
        .toList()
      ..sort();

void main() {
  late Directory tmp;
  late String root;
  late String databases;

  setUp(() async {
    tmp = (await Directory.systemTemp.createTemp('t197-')).absolute;
    final app = Directory(p.join(tmp.path, 'app'))..createSync();
    databases = (Directory(p.join(app.path, 'databases'))..createSync()).path;
    File(p.join(databases, 'secret.db')).writeAsStringSync('CANARY');
    File(p.join(app.path, 'cache', 'decrypted.ogg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('decrypted media');
    final shareRoot = Directory(p.join(app.path, 'cache', sharedMediaDirName))
      ..createSync(recursive: true);
    root = await shareRoot.resolveSymbolicLinks();
    for (final u in [_u1, _u2, _u4]) {
      Directory(p.join(root, u)).createSync();
    }
    File(p.join(root, _u1, 'ok.txt')).writeAsStringSync('12345');
    Link(
      p.join(root, _u2, 'evil.txt'),
    ).createSync(p.join(databases, 'secret.db'));
    Link(p.join(root, _u3)).createSync(databases);
    File(p.join(root, _u4, 'big.bin')).openSync(mode: FileMode.write)
      ..setPositionSync(maxSharedFileBytes)
      ..writeByteSync(1)
      ..closeSync();
  });

  tearDown(() => tmp.delete(recursive: true));

  SharedMediaFile file(String path) =>
      SharedMediaFile(path: path, type: SharedMediaType.file);

  Future<List<String>> run(List<String> paths) async =>
      (await filterSharedMedia(
        paths.map(file).toList(),
        shareRoot: root,
        canonicalize: canonicalSharedPath,
        fileSize: sharedFileSize,
      )).map((f) => f.path).toList();

  test('only the plugin copy survives; everything else is dropped', () async {
    final before = _tree(tmp);
    final result = await run([
      p.join(root, _u1, 'ok.txt'),
      p.join(root, _u2, 'evil.txt'),
      p.join(root, _u3, 'secret.db'),
      p.join(root, _u4, 'big.bin'),
      p.join(tmp.path, 'app', 'cache', 'decrypted.ogg'),
      p.join(databases, 'secret.db'),
      'file://${p.join(databases, 'secret.db')}',
      p.join(root, _u1, 'does-not-exist'),
    ]);
    expect(result, [p.join(root, _u1, 'ok.txt')]);
    expect(File(p.join(databases, 'secret.db')).readAsStringSync(), 'CANARY');
    expect(_tree(tmp), before);
  });

  test(
    'canonicalSharedPath resolves links and returns null for a gap',
    () async {
      expect(
        await canonicalSharedPath(p.join(root, _u2, 'evil.txt')),
        p.join(await Directory(databases).resolveSymbolicLinks(), 'secret.db'),
      );
      expect(await canonicalSharedPath(p.join(root, 'nope')), isNull);
    },
  );

  test('sharedFileSize reports the real size, null when missing', () async {
    expect(await sharedFileSize(p.join(root, _u1, 'ok.txt')), 5);
    expect(await sharedFileSize(p.join(root, _u1, 'nope')), isNull);
  });

  group('deleteStaleSharedCopies', () {
    test('old copies and stray entries go, links are not followed', () async {
      final future = DateTime.now().add(const Duration(minutes: 1));
      final stray = File(p.join(root, 'stray.txt'))..writeAsStringSync('x');
      final removed = await deleteStaleSharedCopies(root, cutoff: future);
      expect(removed, 5);
      expect(Directory(root).listSync(), isEmpty);
      expect(stray.existsSync(), isFalse);
      expect(File(p.join(databases, 'secret.db')).readAsStringSync(), 'CANARY');
    });

    test('a copy newer than the cutoff stays', () async {
      final past = DateTime.now().subtract(const Duration(days: 1));
      Link(p.join(root, _u3)).deleteSync();
      final removed = await deleteStaleSharedCopies(root, cutoff: past);
      expect(removed, 0);
      expect(File(p.join(root, _u1, 'ok.txt')).existsSync(), isTrue);
    });
  });

  group('logging', () {
    const secret = 'evil-sender-name.exe';

    Future<String?> failingRoot() => throw FileSystemException(
      'Cannot resolve',
      p.join('/data/user/0/app/cache', sharedMediaDirName, _u1, secret),
    );

    setUp(() => Logs().outputEvents.clear());

    test('a root failure logs the error type, never a path', () async {
      await filterSharedFiles(const [], resolveRoot: failingRoot);
      final logged = Logs().outputEvents.map((e) => e.toFormattedString());
      expect(logged, isNotEmpty);
      expect(logged.join('\n'), isNot(contains(secret)));
      expect(logged.join('\n'), contains('FileSystemException'));
    });

    test('a cleanup failure logs the error type, never a path', () async {
      await deleteOldSharedCopies(resolveRoot: failingRoot);
      final logged = Logs().outputEvents.map((e) => e.toFormattedString());
      expect(logged, isNotEmpty);
      expect(logged.join('\n'), isNot(contains(secret)));
      expect(logged.join('\n'), contains('FileSystemException'));
    });
  });
}
