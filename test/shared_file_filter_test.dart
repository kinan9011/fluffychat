// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/app_start_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

const _appData = '/data/user/0/im.fluffychat';
const _cache = '/data/user/0/im.fluffychat/cache';

void main() {
  group('isAllowedSharedPath', () {
    for (final path in [
      '$_appData/databases/x.sqlite',
      '$_appData/shared_prefs/FlutterSharedPreferences.xml',
      '$_cache/fluffychat_download_cache/abc',
      _appData,
      '$_cache/../databases/x',
    ]) {
      test('drops $path', () {
        expect(
          isAllowedSharedPath(path, appDataDir: _appData, shareCopyDir: _cache),
          isFalse,
        );
      });
    }

    for (final path in [
      '$_cache/IMG_1.png',
      '/storage/emulated/0/Download/a.pdf',
      '/data/user/0/im.fluffychat.evil/x',
    ]) {
      test('keeps $path', () {
        expect(
          isAllowedSharedPath(path, appDataDir: _appData, shareCopyDir: _cache),
          isTrue,
        );
      });
    }
  });

  group('dropPrivateSharedFiles', () {
    SharedMediaFile file(String path, [SharedMediaType? type]) =>
        SharedMediaFile(path: path, type: type ?? SharedMediaType.file);

    Future<String?> canonicalize(String path) async => switch (path) {
      '/sdcard/missing' => null,
      '/sdcard/link' => '$_appData/databases/x',
      _ => path,
    };

    Future<List<String>> run(List<SharedMediaFile> files) async =>
        (await dropPrivateSharedFiles(
          files,
          canonicalize: canonicalize,
          appDataDir: _appData,
          shareCopyDir: _cache,
        )).map((f) => f.path).toList();

    test('an unresolvable path is dropped', () async {
      expect(await run([file('/sdcard/missing')]), isEmpty);
    });

    test('text and urls pass through', () async {
      expect(
        await run([
          file('$_appData/databases/x', SharedMediaType.text),
          file('https://example.org', SharedMediaType.url),
        ]),
        ['$_appData/databases/x', 'https://example.org'],
      );
    });

    test('a symlink into the app data is dropped', () async {
      expect(await run([file('/sdcard/link')]), isEmpty);
    });

    test('a file url is canonicalised and kept when allowed', () async {
      expect(await run([file('file:///storage/emulated/0/a.png')]), [
        '/storage/emulated/0/a.png',
      ]);
    });

    test('private files are dropped, others stay', () async {
      expect(
        await run([
          file('$_appData/databases/x.sqlite'),
          file('$_cache/IMG_1.png'),
        ]),
        ['$_cache/IMG_1.png'],
      );
    });
  });
}
