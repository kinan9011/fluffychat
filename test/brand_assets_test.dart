// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _png(String path) {
  final image = img.decodePng(File(path).readAsBytesSync());
  if (image == null) throw StateError('not a png: $path');
  return image;
}

List<int> _icoSizes(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final count = data.getUint16(4, Endian.little);
  return [
    for (var i = 0; i < count; i++)
      switch (bytes[6 + i * 16]) {
        0 => 256,
        final size => size,
      },
  ];
}

/// Alpha bounding box as fractions of the canvas.
({double left, double top, double right, double bottom}) _alphaBox(
  img.Image image,
) {
  var left = image.width;
  var top = image.height;
  var right = -1;
  var bottom = -1;
  for (final pixel in image) {
    if (pixel.a == 0) continue;
    if (pixel.x < left) left = pixel.x;
    if (pixel.x > right) right = pixel.x;
    if (pixel.y < top) top = pixel.y;
    if (pixel.y > bottom) bottom = pixel.y;
  }
  return (
    left: left / image.width,
    top: top / image.height,
    right: (right + 1) / image.width,
    bottom: (bottom + 1) / image.height,
  );
}

void main() {
  test('the base artwork has the sizes and channels the generators need', () {
    final logo = _png('assets/logo/img/logo.png');
    expect((logo.width, logo.height), (1024, 1024));
    expect(logo.numChannels, 3, reason: 'opaque, App Store rejects alpha');
    expect(_png('assets/logo/img/logo_standalone.png').numChannels, 3);
    final background = _png('assets/logo/img/logo_background.png');
    expect(background.getPixel(10, 10).r, 255);
    expect(background.getPixel(10, 10).g, 248);
    expect(background.getPixel(10, 10).b, 245);
  });

  test('the adaptive foreground is transparent and inside its safe area', () {
    final foreground = _png('assets/logo/img/logo_foreground.png');
    expect(foreground.hasAlpha, isTrue);
    expect(foreground.getPixel(2, 2).a, 0);
    final box = _alphaBox(foreground);
    for (final edge in [box.left, box.top]) {
      expect(edge, greaterThan(0.01), reason: 'art touches the edge');
    }
    for (final edge in [box.right, box.bottom]) {
      expect(edge, lessThan(0.99), reason: 'art touches the edge');
    }
    expect(box.right - box.left, greaterThan(0.85));
  });

  test('the monochrome art is pure white or transparent', () {
    for (final path in [
      'assets/logo/img/logo_mono.png',
      'assets/logo/mini/logo_mono_mini.png',
    ]) {
      final mono = _png(path);
      var opaque = 0;
      for (final pixel in mono) {
        if (pixel.a == 0) continue;
        opaque++;
        expect(
          (pixel.r, pixel.g, pixel.b),
          (255, 255, 255),
          reason: '$path has a coloured pixel',
        );
      }
      expect(opaque, greaterThan(1000), reason: '$path is empty');
    }
  });

  test('Android launcher icons exist in every density', () {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final MapEntry(key: density, value: size) in sizes.entries) {
      final icon = _png(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      expect((icon.width, icon.height), (size, size), reason: density);
      expect(
        File(
          'android/app/src/main/res/drawable-$density/ic_launcher_foreground.png',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          'android/app/src/main/res/drawable-$density/ic_launcher_monochrome.png',
        ).existsSync(),
        isTrue,
      );
    }
    for (final stale in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
      expect(
        File('android/app/src/main/res/drawable/$stale.xml').existsSync(),
        isFalse,
        reason: 'old vector would shadow the new art',
      );
    }
  });

  test('iOS app icon set is complete and has no alpha', () {
    const set = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final contents =
        jsonDecode(File('$set/Contents.json').readAsStringSync())
            as Map<String, Object?>;
    final images = (contents['images']! as List).cast<Map<String, Object?>>();
    for (final entry in images) {
      final filename = entry['filename'];
      if (filename == null) continue;
      expect(File('$set/$filename').existsSync(), isTrue, reason: '$filename');
    }
    final marketing = _png('$set/Icon-App-1024x1024@1x.png');
    expect((marketing.width, marketing.height), (1024, 1024));
    expect(marketing.numChannels, 3);
  });

  test('macOS, web, Windows and Linux icons exist', () {
    expect(
      _png(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      ).width,
      1024,
    );
    for (final size in [16, 32, 48, 192, 512]) {
      final icon = _png('web/icons/Icon-$size.png');
      expect((icon.width, icon.height), (size, size));
    }
    expect(_png('web/icons/Icon-maskable-512.png').width, 512);
    expect(_icoSizes('windows/runner/resources/app_icon.ico'), [
      256,
      128,
      64,
      48,
      32,
      16,
    ]);
    expect(_png('snap/gui/odango.png').width, 256);
    expect(File('snap/gui/odango.desktop').existsSync(), isTrue);
  });

  test('no artwork of the upstream project is shipped', () {
    final files = [
      for (final entity in Directory('assets/logo').listSync(recursive: true))
        if (entity is File) entity.path,
    ];
    expect(files, isNotEmpty);
    for (final path in files) {
      final name = path.split('/').last;
      expect(name, isNot(startsWith('mascot')));
      expect(name, isNot(startsWith('banner')));
      expect(name, isNot(startsWith('logo_font')));
    }
    expect(Directory('assets/logo/vector').existsSync(), isFalse);
    final reuse = File('REUSE.toml').readAsStringSync();
    expect(reuse, isNot(contains('mascot')));
    expect(reuse, isNot(contains('banner')));
    expect(reuse, isNot(contains('Fabiyamada')));
  });

  test(
    'every file of every app icon set is referenced by its Contents.json',
    () {
      final sets = [
        for (final root in ['ios', 'macos'])
          for (final entity in Directory(root).listSync(recursive: true))
            if (entity is Directory && entity.path.endsWith('.appiconset'))
              entity.path,
      ];
      expect(sets.length, greaterThanOrEqualTo(2));
      for (final set in sets) {
        final contents =
            jsonDecode(File('$set/Contents.json').readAsStringSync())
                as Map<String, Object?>;
        final referenced = {
          for (final entry
              in (contents['images']! as List).cast<Map<String, Object?>>())
            if (entry['filename'] case final String name) name,
        };
        final present = {
          for (final entity in Directory(set).listSync())
            if (entity is File && !entity.path.endsWith('Contents.json'))
              entity.path.split('/').last,
        };
        expect(present.difference(referenced), isEmpty, reason: '$set orphans');
        expect(referenced.difference(present), isEmpty, reason: '$set missing');
      }
    },
  );

  test('no image anywhere is byte-identical to removed upstream artwork', () {
    final known = {
      for (final line in File(
        'test/data/upstream_art.sha256',
      ).readAsLinesSync())
        if (line.isNotEmpty) line.split('  ').first: line.split('  ').last,
    };
    expect(known.length, greaterThan(80));
    final listing = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
    final hits = <String>[];
    for (final path in LineSplitter.split(listing.stdout.toString())) {
      final lower = path.toLowerCase();
      if (!const [
        '.png',
        '.jpg',
        '.jpeg',
        '.ico',
        '.icns',
        '.webp',
        '.gif',
        '.svg',
      ].any(lower.endsWith)) {
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) continue;
      final upstream = known[sha256.convert(file.readAsBytesSync()).toString()];
      if (upstream != null) hits.add('$path == upstream $upstream');
    }
    expect(hits, isEmpty, reason: hits.take(10).join('\n'));
  });

  test(
    'the macOS icons are a rounded tile with a margin, not a full bleed',
    () {
      const set = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final size in [1024, 512, 256, 128, 64, 32, 16]) {
        final icon = _png('$set/app_icon_$size.png');
        expect((icon.width, icon.height), (size, size));
        expect(icon.hasAlpha, isTrue, reason: '$size');
        expect(icon.getPixel(0, 0).a, 0, reason: '$size corner');
        expect(
          icon.getPixel(size ~/ 2, size ~/ 2).a,
          255,
          reason: '$size centre',
        );
        if (size < 128) continue;
        final box = _alphaBox(icon);
        for (final margin in [
          box.left,
          box.top,
          1 - box.right,
          1 - box.bottom,
        ]) {
          expect(margin, inInclusiveRange(0.07, 0.13), reason: '$size margin');
        }
      }
    },
  );

  test('generated images carry no provenance or text chunks', () {
    final roots = [
      'assets/logo',
      'android/app/src/main/res',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset',
      'macos/Runner/Assets.xcassets/AppIcon.appiconset',
      'web/icons',
      'snap/gui',
    ];
    const forbidden = ['c2pa', 'tEXt', 'iTXt', 'zTXt', 'eXIf', 'Inkscape'];
    final hits = <String>[];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.png')) continue;
        final text = latin1.decode(entity.readAsBytesSync());
        for (final needle in forbidden) {
          if (text.contains(needle)) hits.add('${entity.path}: $needle');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.take(10).join('\n'));
  });
}
