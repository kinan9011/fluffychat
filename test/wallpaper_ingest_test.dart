// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';
import 'package:odango/utils/appearance/wallpaper_ingest.dart';

Uint8List _jpeg(int width, int height, {bool gps = false, int? orientation}) {
  final image = Image(width: width, height: height);
  fill(image, color: ColorRgb8(200, 30, 30));
  if (gps) {
    image.exif.gpsIfd['GPSLatitudeRef'] = 'N';
    image.exif.gpsIfd['GPSLongitudeRef'] = 'E';
    image.exif.imageIfd['Make'] = 'SecretPhoneMaker';
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return encodeJpg(image, quality: 95);
}

Uint8List _pngHeader(int width, int height) {
  final builder = BytesBuilder();
  builder.add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> body) {
    final length = ByteData(4)..setUint32(0, body.length);
    builder.add(length.buffer.asUint8List());
    final typed = [...type.codeUnits, ...body];
    builder.add(typed);
    final crc = ByteData(4)..setUint32(0, getCrc32(typed));
    builder.add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', const [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]);
  chunk('IEND', const []);
  return builder.toBytes();
}

/// A GIF whose frames are one pixel each, on a [canvas] x [canvas] screen:
/// tiny on disk, but a decoder that composites every frame onto the full
/// canvas needs [frames] x [canvas] x [canvas] pixels. Frame 0 is red, the
/// others blue.
Uint8List _animatedGif({required int canvas, required int frames}) {
  List<int> le16(int v) => [v & 0xFF, v >> 8];
  final out = BytesBuilder()
    ..add('GIF89a'.codeUnits)
    ..add(le16(canvas))
    ..add(le16(canvas))
    ..add([0x80, 0, 0])
    ..add([255, 0, 0, 0, 0, 255]);
  for (var i = 0; i < frames; i++) {
    out
      ..add([0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00])
      ..add([0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0x00])
      ..add(
        i == 0
            ? [0x02, 0x02, 0x44, 0x01, 0x00]
            : [0x02, 0x02, 0x4C, 0x01, 0x00],
      );
  }
  out.addByte(0x3B);
  return out.toBytes();
}

bool _contains(Uint8List haystack, String needle) {
  final n = needle.codeUnits;
  for (var i = 0; i <= haystack.length - n.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  WallpaperRejection? rejection(void Function() run) {
    try {
      run();
    } on WallpaperRejected catch (e) {
      return e.reason;
    }
    return null;
  }

  test('input above 15 MB is rejected before anything is parsed', () {
    final huge = Uint8List(WallpaperIngest.maxInputBytes + 1);
    expect(
      rejection(() => WallpaperIngest.checkHeader(huge)),
      WallpaperRejection.tooLarge,
    );
  });

  test('a file that is not an image is rejected', () {
    expect(
      rejection(
        () => WallpaperIngest.checkHeader(
          Uint8List.fromList('not an image at all'.codeUnits),
        ),
      ),
      WallpaperRejection.notAnImage,
    );
    expect(
      rejection(() => WallpaperIngest.checkHeader(Uint8List(0))),
      WallpaperRejection.notAnImage,
    );
  });

  test('too many pixels are rejected from the header alone', () {
    expect(
      rejection(() => WallpaperIngest.checkHeader(_pngHeader(8000, 6000))),
      WallpaperRejection.tooManyPixels,
    );
  });

  test('a header the decoder itself refuses is rejected', () {
    expect(
      rejection(() => WallpaperIngest.checkHeader(_pngHeader(20000, 20000))),
      isNotNull,
    );
  });

  test('a large photo is resized to a longest edge of 2048', () {
    final out = WallpaperIngest.encodeSync(_jpeg(4000, 3000));
    final decoded = decodeJpg(out)!;
    expect(decoded.width, 2048);
    expect(decoded.height, 1536);
  });

  test('a portrait photo is limited on its height', () {
    final decoded = decodeJpg(WallpaperIngest.encodeSync(_jpeg(3000, 4000)))!;
    expect(decoded.height, 2048);
    expect(decoded.width, 1536);
  });

  test('a small photo is never upscaled', () {
    final decoded = decodeJpg(WallpaperIngest.encodeSync(_jpeg(300, 200)))!;
    expect(decoded.width, 300);
    expect(decoded.height, 200);
  });

  test('GPS and other EXIF data do not survive', () {
    final input = _jpeg(400, 300, gps: true);
    expect(_contains(input, 'SecretPhoneMaker'), isTrue);
    final out = WallpaperIngest.encodeSync(input);
    expect(decodeJpg(out)!.exif.isEmpty, isTrue);
    expect(_contains(out, 'SecretPhoneMaker'), isFalse);
    expect(_contains(out, 'Exif'), isFalse);
  });

  test('the orientation is baked into the pixels', () {
    final out = WallpaperIngest.encodeSync(_jpeg(400, 300, orientation: 6));
    final decoded = decodeJpg(out)!;
    expect(decoded.width, 300);
    expect(decoded.height, 400);
    expect(decoded.exif.imageIfd.hasOrientation, isFalse);
  });

  test('the output stays under 4 MB', () {
    final out = WallpaperIngest.encodeSync(_jpeg(2000, 2000));
    expect(out.length, lessThanOrEqualTo(WallpaperIngest.maxOutputBytes));
  });

  test('process runs the same checks and returns a jpeg', () async {
    final out = await WallpaperIngest.process(_jpeg(500, 500, gps: true));
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
    await expectLater(
      WallpaperIngest.process(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<WallpaperRejected>()),
    );
  });

  group('animated images: only the first frame is decoded', () {
    test('a two frame GIF becomes a wallpaper from its first frame', () {
      final out = WallpaperIngest.encodeSync(
        _animatedGif(canvas: 1, frames: 2),
      );
      final pixel = decodeJpg(out)!.getPixel(0, 0);
      expect(pixel.r, greaterThan(150));
      expect(pixel.b, lessThan(100));
    });

    test('many frames on a large canvas do not multiply the work', () {
      final bomb = _animatedGif(canvas: 6000, frames: 8);
      expect(bomb.length, lessThan(1000));
      WallpaperIngest.checkHeader(bomb);
      final decoded = decodeJpg(WallpaperIngest.encodeSync(bomb))!;
      expect(decoded.width, lessThanOrEqualTo(WallpaperIngest.maxEdge));
    });

    test('process accepts the same file', () async {
      final out = await WallpaperIngest.process(
        _animatedGif(canvas: 6000, frames: 8),
      );
      expect(out[0], 0xFF);
    });
  });
}
