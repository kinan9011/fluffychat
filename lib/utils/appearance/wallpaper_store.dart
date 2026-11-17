// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The custom wallpaper: one file at a fixed path in the app support
/// directory. Nothing the user picked or any Matrix content decides the path
/// and the photo never leaves the device.
class LocalWallpaperStore {
  LocalWallpaperStore({Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationSupportDirectory;

  static const folderName = 'wallpapers';
  static const fileName = 'custom.jpg';

  static bool get supported => !kIsWeb;

  final Future<Directory> Function() _baseDir;

  Future<File> _file() async =>
      File('${(await _baseDir()).path}/$folderName/$fileName');

  Future<File?> current() async {
    if (!supported) return null;
    final file = await _file();
    return await file.exists() ? file : null;
  }

  Future<void> save(Uint8List processed) async {
    if (!supported) return;
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(processed, flush: true);
  }

  Future<void> clear() async {
    if (!supported) return;
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
