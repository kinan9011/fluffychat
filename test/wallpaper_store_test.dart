// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/appearance/wallpaper_store.dart';

void main() {
  late Directory base;
  late LocalWallpaperStore store;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('wallpaper_store_test');
    store = LocalWallpaperStore(baseDir: () async => base);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  List<String> files() => base
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.substring(base.path.length))
      .toList();

  test('there is no wallpaper at first', () async {
    expect(await store.current(), isNull);
  });

  test('save writes exactly one file at the fixed path', () async {
    await store.save(Uint8List.fromList([1, 2, 3]));
    expect(files(), ['/wallpapers/custom.jpg']);
    final file = await store.current();
    expect(await file!.readAsBytes(), [1, 2, 3]);
  });

  test('saving again replaces the file and creates no other', () async {
    await store.save(Uint8List.fromList([1]));
    await store.save(Uint8List.fromList([2, 2]));
    expect(files(), ['/wallpapers/custom.jpg']);
    expect(await (await store.current())!.readAsBytes(), [2, 2]);
  });

  test('clear removes the file', () async {
    await store.save(Uint8List.fromList([1]));
    await store.clear();
    expect(files(), isEmpty);
    expect(await store.current(), isNull);
    await store.clear();
  });
}
