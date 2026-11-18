// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/utils/image_pixel_cap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';
import 'package:matrix/matrix.dart';

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Uint8List _png(int width, int height) {
  final bytes = Uint8List.fromList(encodePng(Image(width: 1, height: 1)));
  final view = ByteData.sublistView(bytes)
    ..setUint32(16, width)
    ..setUint32(20, height);
  view.setUint32(29, _crc32(bytes.sublist(12, 29)));
  return bytes;
}

class _NeverCalled extends NativeImplementations {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('decoded a picture that is over the cap');
}

void main() {
  test('a small image is within the cap', () {
    expect(imageWithinPixelCap(_png(256, 256)), isTrue);
    expect(imageWithinPixelCap(_png(6000, 6000)), isTrue);
  });

  test('a header that declares more than 40 megapixels is refused', () {
    expect(imageWithinPixelCap(_png(7000, 7000)), isFalse);
    expect(imageWithinPixelCap(_png(60000, 60000)), isFalse);
    expect(imageWithinPixelCap(_png(1 << 30, 1 << 30)), isFalse);
  });

  test('bytes that are not an image are refused, never thrown', () {
    expect(imageWithinPixelCap(Uint8List.fromList([1, 2, 3])), isFalse);
    expect(imageWithinPixelCap(Uint8List(0)), isFalse);
    expect(imageWithinPixelCap(_png(0, 0)), isFalse);
  });

  group('emoteThumbnail', () {
    test(
      'an oversized picture is refused before anything decodes it',
      () async {
        final result = await emoteThumbnail(
          MatrixImageFile(bytes: _png(60000, 60000), name: 'bomb.png'),
          nativeImplementations: _NeverCalled(),
        );
        expect(result, isNull);
      },
    );

    test('a picture that no decoder here knows is refused', () async {
      final result = await emoteThumbnail(
        MatrixImageFile(bytes: Uint8List.fromList([1, 2, 3]), name: 'x.heic'),
        nativeImplementations: _NeverCalled(),
      );
      expect(result, isNull);
    });

    test('a normal picture goes on to the thumbnail step', () async {
      final bytes = Uint8List.fromList(encodePng(Image(width: 64, height: 64)));
      final result = await emoteThumbnail(
        MatrixImageFile(bytes: bytes, name: 'ok.png'),
        nativeImplementations: NativeImplementations.dummy,
      );
      expect(result, isNotNull);
    });
  });

  test('a real encoded image passes', () {
    final bytes = encodePng(Image(width: 32, height: 32));
    expect(imageWithinPixelCap(bytes), isTrue);
  });
}
