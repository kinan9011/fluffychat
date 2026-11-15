// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeDisplayText', () {
    test('keeps plain text untouched', () {
      expect(safeDisplayText('Alice B.'), 'Alice B.');
    });

    test('collapses line breaks and runs of whitespace', () {
      expect(safeDisplayText('a\n\n\n b\t\tc\r\nd'), 'a b c d');
    });

    test('drops bidi override and isolate characters', () {
      expect(safeDisplayText('invoice\u202Efdp.exe'), 'invoice fdp.exe');
      expect(safeDisplayText('\u2067x\u2069\u200Ey\u200F'), 'x y');
    });

    test('drops zero width, control and tag characters', () {
      expect(
        safeDisplayText('a\u200Bb\u2060c\uFEFFd\u0000e\u0085f'),
        'a b c d e f',
      );
      expect(safeDisplayText('a${String.fromCharCode(0xE0041)}b'), 'a b');
    });

    test('caps by grapheme without splitting clusters', () {
      final family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}' * 100;
      final out = safeDisplayText(family, maxGraphemes: 5);
      expect(out.characters.length, 5);
      expect(out.characters.first, '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}');
      expect(out.endsWith('…'), isTrue);
    });

    test('short text is not given an ellipsis', () {
      expect(safeDisplayText('abcde', maxGraphemes: 5), 'abcde');
      expect(safeDisplayText('abcdef', maxGraphemes: 5), 'abcd…');
    });

    test('a stack of combining marks is cut to three (SEC S-N1)', () {
      final zalgo = 'B${'\u0489' * 300}x';
      expect(safeDisplayText(zalgo), 'B\u0489\u0489\u0489x');
      expect(safeDisplayText('a\u0301\u0302b'), 'a\u0301\u0302b');
    });

    test('emoji with a variation selector and a keycap survive', () {
      expect(safeDisplayText('1\uFE0F\u20E3'), '1\uFE0F\u20E3');
    });

    test('only hostile characters yields empty text', () {
      expect(safeDisplayText('\u202E\n\u200B'), '');
    });
  });

  group('isolatedDisplayText', () {
    test('wraps in first strong isolate and pop isolate', () {
      final out = isolatedDisplayText('x\u202Ey');
      expect(out.startsWith('\u2068'), isTrue);
      expect(out.endsWith('\u2069'), isTrue);
      expect(out.contains('\u202E'), isFalse);
      expect(out, '\u2068x y\u2069');
    });
  });
}
