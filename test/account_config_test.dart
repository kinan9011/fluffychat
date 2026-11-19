// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/account_config.dart';

void main() {
  group('wallpaper_url', () {
    test('an mxc uri is accepted', () {
      final config = ApplicationAccountConfig.fromJson({
        'wallpaper_url': 'mxc://example.org/abc',
      });
      expect(config.wallpaperUrl.toString(), 'mxc://example.org/abc');
    });

    for (final bad in [
      'javascript:alert(1)',
      'http://example.org/a.png',
      'https://example.org/a.png',
      'file:///etc/passwd',
      'data:image/png;base64,AAAA',
      '',
      'not a uri at all',
    ]) {
      test('"$bad" is dropped', () {
        expect(
          ApplicationAccountConfig.fromJson({
            'wallpaper_url': bad,
          }).wallpaperUrl,
          isNull,
        );
      });
    }

    test('non string values are dropped', () {
      expect(
        ApplicationAccountConfig.fromJson({'wallpaper_url': 5}).wallpaperUrl,
        isNull,
      );
    });

    test('an overlong value is dropped', () {
      expect(
        ApplicationAccountConfig.fromJson({
          'wallpaper_url': 'mxc://example.org/${'a' * 3000}',
        }).wallpaperUrl,
        isNull,
      );
    });
  });

  group('wallpaper_blur', () {
    test('is clamped to 0..50', () {
      expect(
        ApplicationAccountConfig.fromJson({
          'wallpaper_blur': 900.0,
        }).wallpaperBlur,
        50,
      );
      expect(
        ApplicationAccountConfig.fromJson({
          'wallpaper_blur': -4.0,
        }).wallpaperBlur,
        0,
      );
      expect(
        ApplicationAccountConfig.fromJson({
          'wallpaper_blur': 12.5,
        }).wallpaperBlur,
        12.5,
      );
    });

    test('a non finite value is dropped', () {
      expect(
        ApplicationAccountConfig.fromJson({
          'wallpaper_blur': double.infinity,
        }).wallpaperBlur,
        isNull,
      );
    });
  });
}
