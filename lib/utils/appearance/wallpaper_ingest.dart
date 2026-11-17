// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:image/image.dart';

enum WallpaperRejection { tooLarge, notAnImage, tooManyPixels, tooBig }

class WallpaperRejected implements Exception {
  const WallpaperRejected(this.reason);

  final WallpaperRejection reason;

  @override
  String toString() => 'WallpaperRejected(${reason.name})';
}

/// Turns a photo the user picked into a bounded, metadata free JPEG. The file
/// is untrusted: it is size checked, its header is read before any pixel is
/// decoded, and it is always re-encoded, which drops EXIF (GPS), ICC and
/// every other embedded block. Only the first frame of an animation is
/// decoded: every frame is composited onto a full canvas, so a small file can
/// need gigabytes.
abstract class WallpaperIngest {
  static const maxInputBytes = 15 * 1024 * 1024;
  static const maxPixels = 40 * 1000 * 1000;
  static const maxEdge = 2048;
  static const maxOutputBytes = 4 * 1024 * 1024;
  static const _qualities = [85, 70, 55];

  static Future<Uint8List> process(Uint8List input) => Future.sync(() {
    checkHeader(input);
    return compute(encodeSync, input);
  });

  @visibleForTesting
  static void checkHeader(Uint8List input) {
    if (input.length > maxInputBytes) {
      throw const WallpaperRejected(WallpaperRejection.tooLarge);
    }
    DecodeInfo? info;
    try {
      info = findDecoderForData(input)?.startDecode(input);
    } catch (_) {
      throw const WallpaperRejected(WallpaperRejection.notAnImage);
    }
    if (info == null || info.width <= 0 || info.height <= 0) {
      throw const WallpaperRejected(WallpaperRejection.notAnImage);
    }
    if (info.width * info.height > maxPixels) {
      throw const WallpaperRejected(WallpaperRejection.tooManyPixels);
    }
  }

  @visibleForTesting
  static Uint8List encodeSync(Uint8List input) {
    checkHeader(input);
    Image? decoded;
    try {
      decoded = decodeImage(input, frame: 0);
    } catch (_) {
      throw const WallpaperRejected(WallpaperRejection.notAnImage);
    }
    if (decoded == null) {
      throw const WallpaperRejected(WallpaperRejection.notAnImage);
    }
    var image = bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxEdge) {
      image = image.width >= image.height
          ? copyResize(image, width: maxEdge)
          : copyResize(image, height: maxEdge);
    }
    image
      ..exif = ExifData()
      ..iccProfile = null;
    for (final quality in _qualities) {
      final bytes = encodeJpg(image, quality: quality);
      if (bytes.length <= maxOutputBytes) return bytes;
    }
    throw const WallpaperRejected(WallpaperRejection.tooBig);
  }
}
