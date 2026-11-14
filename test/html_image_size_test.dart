// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/html_image_size.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;

void main() {
  group('htmlImageSize', () {
    test('missing attributes fall back to default square', () {
      final size = htmlImageSize(null, null);
      expect(size.width, htmlImageDefaultDimension);
      expect(size.height, htmlImageDefaultDimension);
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

  group('limitHtmlImages', () {
    const image = '<img src="mxc://a/b" alt="x">';

    test('replaces every image above the cap with its alt text', () {
      final body = parser.parse('<p>${image * 200}</p>').body!;

      expect(limitHtmlImages(body), 150);
      expect(body.querySelectorAll('img'), hasLength(htmlMaxImagesPerMessage));
      expect(body.text, 'x' * 150);
    });

    test('keeps a message at the cap untouched', () {
      final body = parser.parse('<p>${image * 50}</p>').body!;

      expect(limitHtmlImages(body), 0);
      expect(body.querySelectorAll('img'), hasLength(50));
    });

    test('a missing alt text becomes empty text', () {
      final body = parser
          .parse('<img src="mxc://a/b"><img src="mxc://a/c">')
          .body!;

      expect(limitHtmlImages(body, 1), 1);
      expect(body.querySelectorAll('img'), hasLength(1));
    });
  });
}
