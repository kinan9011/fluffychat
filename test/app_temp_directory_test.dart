// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/app_temp_directory.dart';

void main() {
  late Directory base;

  setUp(() => base = Directory.systemTemp.createTempSync('app_temp_test'));

  tearDown(() => base.deleteSync(recursive: true));

  Future<Directory> baseDir() async => base;

  test('the app temp directory is a created child of the cache (G1)', () async {
    final dir = await appTempDirectory(base: baseDir);

    expect(dir.path, '${base.path}/odango_tmp');
    expect(dir.existsSync(), isTrue);
  });

  test('looking for it never creates it', () async {
    expect(await appTempDirectoryIfExists(base: baseDir), isNull);
    expect(base.listSync(), isEmpty);

    await appTempDirectory(base: baseDir);

    expect(await appTempDirectoryIfExists(base: baseDir), isNotNull);
  });

  test(
    'deleting removes it with its files and keeps its siblings (G2)',
    () async {
      final dir = await appTempDirectory(base: baseDir);
      File('${dir.path}/voice_message_1.opus').writeAsBytesSync([1]);
      final sibling = File('${base.path}/plugin_copy')..writeAsBytesSync([2]);

      await deleteAppTempDirectory(base: baseDir);

      expect(dir.existsSync(), isFalse);
      expect(sibling.existsSync(), isTrue);
    },
  );

  test('deleting when there is nothing is fine', () async {
    await deleteAppTempDirectory(base: baseDir);

    expect(base.listSync(), isEmpty);
  });

  test('on Linux the base is the app cache, not the shared /tmp', () {
    expect(
      File('lib/utils/app_temp_directory.dart').readAsStringSync(),
      contains('getApplicationCacheDirectory'),
    );
  });

  test('the three writers use it, none writes into the cache root (G3)', () {
    for (final path in [
      'lib/pages/chat/events/audio_player.dart',
      'lib/pages/image_viewer/video_player.dart',
      'lib/pages/chat/recording_view_model.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('appTempDirectory()'), reason: path);
      expect(source, isNot(contains('getTemporaryDirectory')), reason: path);
    }
  });

  test('the start-up sweep removes what a previous run left (S6)', () async {
    final dir = await appTempDirectory(base: baseDir);
    File('${dir.path}/audio_1.opus').writeAsBytesSync([1]);
    final sibling = File('${base.path}/plugin_copy')..writeAsBytesSync([2]);

    await sweepAppTempDirectory(base: baseDir);

    expect(dir.existsSync(), isFalse);
    expect(sibling.existsSync(), isTrue);
  });

  test('the start-up sweep never throws (S6)', () async {
    await sweepAppTempDirectory(
      base: () async => throw const FileSystemException('x'),
    );
  });

  test('main sweeps before any client or player exists (S6)', () {
    final source = File('lib/main.dart').readAsStringSync();
    final sweep = source.indexOf('sweepAppTempDirectory()');

    expect(sweep, isNonNegative);
    expect(sweep, lessThan(source.indexOf('ClientManager.getClients(')));
  });
}
