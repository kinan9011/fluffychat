// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:image/image.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/client_manager.dart';

const maxDecodedPixels = 40 * 1000 * 1000;

/// An image from someone else can declare huge dimensions in a tiny file. Only
/// the header is read here, before any pixel is decoded.
bool imageWithinPixelCap(Uint8List bytes, {int maxPixels = maxDecodedPixels}) {
  try {
    final info = findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return false;
    return info.width * info.height <= maxPixels;
  } catch (_) {
    return false;
  }
}

/// The thumbnail of an emote or sticker picture, or null when the picture
/// declares more pixels than are decoded: an emote pack comes from someone
/// else and a tiny file can claim gigabytes of pixels. A picture whose format
/// is not known here cannot be shrunk by the decoder either, so it is refused
/// as well.
Future<MatrixImageFile?> emoteThumbnail(
  MatrixImageFile file, {
  NativeImplementations? nativeImplementations,
}) async {
  if (!imageWithinPixelCap(file.bytes)) return null;
  return await file.generateThumbnail(
        nativeImplementations:
            nativeImplementations ?? ClientManager.nativeImplementations,
      ) ??
      file;
}
