// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/shared_media_filter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

const _appData = '/data/user/0/com.swovo.odango';
const _cache = '$_appData/cache';
const _root = '$_cache/receive_sharing_intent';
const _u = '123e4567-e89b-12d3-a456-426614174000';
const _iosRoot =
    '/private/var/mobile/Containers/Shared/AppGroup/ABC/receive_sharing_intent';

void main() {
  group('isPluginShareCopy', () {
    for (final (path, root) in [
      ('$_root/$_u/IMG_1.png', _root),
      ('$_root/$_u/Invoice 2026.pdf', _root),
      ('$_root/${_u.toUpperCase()}/a.png', _root),
      ('$_iosRoot/$_u/a.jpg', _iosRoot),
    ]) {
      test('keeps $path', () {
        expect(isPluginShareCopy(path, shareRoot: root), isTrue);
      });
    }

    for (final path in [
      '$_cache/../databases/x',
      '$_root/$_u/../../databases/x',
      '$_root/$_u/../x',
      '$_appData/shared_prefs/FlutterSharedPreferences.xml',
      '$_appData/databases/x.sqlite',
      '$_cache/IMG_1.png',
      '$_cache/odango_download_cache/abc',
      '$_root/a.png',
      '$_root/not-a-uuid/a.png',
      '$_root/$_u/sub/a.png',
      '$_root/$_u',
      _root,
      'receive_sharing_intent/$_u/a.png',
      '/storage/emulated/0/Download/a.pdf',
      '/data/user/0/com.swovo.odango.evil/receive_sharing_intent/$_u/a.png',
    ]) {
      test('drops $path', () {
        expect(isPluginShareCopy(path, shareRoot: _root), isFalse);
      });
    }
  });

  test(
    'a relative path is never a plugin copy, even below a relative root',
    () {
      expect(
        isPluginShareCopy(
          'receive_sharing_intent/$_u/a.png',
          shareRoot: 'receive_sharing_intent',
        ),
        isFalse,
      );
    },
  );

  group('filterSharedMedia', () {
    SharedMediaFile file(
      String path, {
      SharedMediaType? type,
      String? thumbnail,
    }) => SharedMediaFile(
      path: path,
      type: type ?? SharedMediaType.file,
      thumbnail: thumbnail,
      mimeType: 'image/png',
      duration: 7,
      message: 'hello',
    );

    Future<String?> canonicalize(String path) async => switch (path) {
      '$_root/$_u/missing' => null,
      '$_root/$_u/link' => '$_appData/databases/x',
      _ => path,
    };

    Future<int?> fileSize(String path) async => switch (path) {
      '$_root/$_u/big' => maxSharedFileBytes + 1,
      '$_root/$_u/edge' => maxSharedFileBytes,
      '$_root/$_u/unknown' => null,
      _ => 10,
    };

    Future<List<SharedMediaFile>> run(
      List<SharedMediaFile> files, {
      String? root = _root,
    }) => filterSharedMedia(
      files,
      shareRoot: root,
      canonicalize: canonicalize,
      fileSize: fileSize,
    );

    Future<List<String>> paths(List<SharedMediaFile> files) async =>
        (await run(files)).map((f) => f.path).toList();

    test('a file in a plugin share directory is kept', () async {
      expect(await paths([file('$_root/$_u/a.png')]), ['$_root/$_u/a.png']);
    });

    test('a file over the size cap is dropped, one at the cap stays', () async {
      expect(await paths([file('$_root/$_u/big')]), isEmpty);
      expect(await paths([file('$_root/$_u/edge')]), ['$_root/$_u/edge']);
    });

    test('a file of unknown size is dropped', () async {
      expect(await paths([file('$_root/$_u/unknown')]), isEmpty);
    });

    test('the plugin thumbnail path is never passed on', () async {
      final result = await run([
        file('$_root/$_u/a.png', thumbnail: '$_cache/x.png'),
      ]);
      expect(result.single.thumbnail, isNull);
      expect(result.single.duration, 7);
      expect(result.single.mimeType, 'image/png');
      expect(result.single.message, 'hello');
    });

    test('a file url is canonicalised and kept when allowed', () async {
      expect(await paths([file('file://$_root/$_u/a.png')]), [
        '$_root/$_u/a.png',
      ]);
    });

    test('a symlink into the app data is dropped', () async {
      expect(await paths([file('$_root/$_u/link')]), isEmpty);
    });

    test('an unresolvable path is dropped', () async {
      expect(await paths([file('$_root/$_u/missing')]), isEmpty);
    });

    test('raw paths outside the share directories are dropped', () async {
      expect(
        await paths([
          file('/storage/emulated/0/Download/a.pdf'),
          file('$_cache/IMG_1.png'),
          file('$_appData/databases/x.sqlite'),
        ]),
        isEmpty,
      );
    });

    test('text and urls pass through unchanged', () async {
      expect(
        await paths([
          file('$_appData/databases/x', type: SharedMediaType.text),
          file('https://example.org', type: SharedMediaType.url),
        ]),
        ['$_appData/databases/x', 'https://example.org'],
      );
    });

    test('without a share root every file is dropped, text stays', () async {
      final result = await run([
        file('$_root/$_u/a.png'),
        file('hi', type: SharedMediaType.text),
      ], root: null);
      expect(result.map((f) => f.path), ['hi']);
    });

    test('the order of mixed entries is kept', () async {
      expect(
        await paths([
          file('$_root/$_u/1.png'),
          file('$_appData/databases/x'),
          file('t', type: SharedMediaType.text),
          file('$_root/$_u/2.png'),
        ]),
        ['$_root/$_u/1.png', 't', '$_root/$_u/2.png'],
      );
    });
  });
}
