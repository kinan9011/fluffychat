// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/html_image_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('htmlImageSize', () {
    test('missing attributes fall back to default square', () {
      final size = htmlImageSize(null, null);
      expect(size.width, htmlImageDefaultDimension);
      expect(size.height, htmlImageDefaultDimension);
      expect(size.isThumbnail, isFalse);
    });

    test('regular emote size is kept', () {
      final size = htmlImageSize(null, '32');
      expect(size.width, 32);
      expect(size.height, 32);
    });

    test('huge values are scaled down keeping the aspect ratio', () {
      final size = htmlImageSize('100000', '50000');
      expect(size.width, htmlImageMaxDimension);
      expect(size.height, htmlImageMaxDimension / 2);
      expect(size.isThumbnail, isTrue);
    });

    test('a single huge dimension is capped', () {
      final size = htmlImageSize('1e300', null);
      expect(size.width, htmlImageMaxDimension);
      expect(size.height, htmlImageMaxDimension);
    });

    test('extreme aspect ratio keeps a visible minimum', () {
      final size = htmlImageSize('100000', '1');
      expect(size.width, htmlImageMaxDimension);
      expect(size.height, greaterThanOrEqualTo(htmlImageMinDimension));
    });

    for (final invalid in ['NaN', 'Infinity', '-Infinity', '-5', '0', 'abc']) {
      test('invalid value "$invalid" is ignored', () {
        final size = htmlImageSize(invalid, invalid);
        expect(size.width, htmlImageDefaultDimension);
        expect(size.height, htmlImageDefaultDimension);
      });
    }

    test('invalid width falls back to valid height', () {
      final size = htmlImageSize('-1', '48');
      expect(size.width, 48);
      expect(size.height, 48);
    });

    test('results are always finite and within bounds', () {
      for (final w in ['1e-300', '0.0001', '255.9', '256', '257', '1e20']) {
        for (final h in [null, '1e-300', '3', '1e20']) {
          final size = htmlImageSize(w, h);
          for (final value in [size.width, size.height]) {
            expect(value.isFinite, isTrue);
            expect(value, greaterThanOrEqualTo(htmlImageMinDimension));
            expect(value, lessThanOrEqualTo(htmlImageMaxDimension));
          }
        }
      }
    });
  });
}
