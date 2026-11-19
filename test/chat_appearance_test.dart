// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/appearance/chat_appearance.dart';
import 'package:odango/utils/chat/bubble_shape.dart';

void main() {
  group('RoomAppearance.tryParse', () {
    test('accepts a full valid document', () {
      final parsed = RoomAppearance.tryParse({
        'v': 1,
        'preset': 'sunset',
        'accent_hue': 200,
        'corners': 'round',
      });
      expect(parsed?.preset, 'sunset');
      expect(parsed?.accentHue, 200);
      expect(parsed?.corners, BubbleCorners.round);
    });

    test('drops fields that are off schema, keeps the valid ones', () {
      final parsed = RoomAppearance.tryParse({
        'v': 1,
        'preset': '<script>alert(1)</script>',
        'accent_hue': 360,
        'corners': 'round',
      });
      expect(parsed?.preset, isNull);
      expect(parsed?.accentHue, isNull);
      expect(parsed?.corners, BubbleCorners.round);
    });

    for (final bad in <Object?>[360, -1, 12.5, '268', null, true, 268.0]) {
      test('accent_hue $bad is dropped', () {
        final parsed = RoomAppearance.tryParse({
          'v': 1,
          'accent_hue': bad,
          'corners': 'sharp',
        });
        expect(parsed?.accentHue, isNull);
        expect(parsed?.corners, BubbleCorners.sharp);
      });
    }

    test('accent_hue 0 and 359 are valid', () {
      expect(RoomAppearance.tryParse({'v': 1, 'accent_hue': 0})?.accentHue, 0);
      expect(
        RoomAppearance.tryParse({'v': 1, 'accent_hue': 359})?.accentHue,
        359,
      );
    });

    test('an unknown preset id is dropped', () {
      expect(
        RoomAppearance.tryParse({
          'v': 1,
          'preset': 'https://evil.example/x.png',
          'corners': 'sharp',
        })?.preset,
        isNull,
      );
    });

    test('content above 512 bytes is rejected', () {
      expect(
        RoomAppearance.tryParse({
          'v': 1,
          'preset': 'sunset',
          'junk': 'x' * 600,
        }),
        isNull,
      );
    });

    test('wrong version, non map, no valid field are null', () {
      expect(RoomAppearance.tryParse({'v': 2, 'preset': 'night'}), isNull);
      expect(RoomAppearance.tryParse('night'), isNull);
      expect(RoomAppearance.tryParse(null), isNull);
      expect(RoomAppearance.tryParse(<String, Object?>{}), isNull);
      expect(RoomAppearance.tryParse({'v': 1}), isNull);
      expect(RoomAppearance.tryParse({'v': 1, 'preset': 5}), isNull);
    });

    test('non string keys are rejected', () {
      expect(RoomAppearance.tryParse({1: 'a', 'v': 1}), isNull);
    });

    test('toContent writes known keys only', () {
      final parsed = RoomAppearance.tryParse({
        'v': 1,
        'preset': 'night',
        'unknown': 'x',
        'nested': {'a': 1},
      })!;
      expect(parsed.toContent(), {'v': 1, 'preset': 'night'});
    });
  });

  group('resolveAppearance', () {
    const global = GlobalAppearance(
      preset: 'default',
      accentHue: 268,
      corners: BubbleCorners.standard,
    );

    test('room values win per field', () {
      final resolved = resolveAppearance(
        global: global,
        room: const RoomAppearance(preset: 'night', accentHue: 25),
      );
      expect(resolved.preset, 'night');
      expect(resolved.accentHue, 25);
      expect(resolved.corners, BubbleCorners.standard);
      expect(resolved.hasRoomOverride, isTrue);
      expect(resolved.hasRoomPreset, isTrue);
    });

    test('a room that only changes the accent has no preset of its own', () {
      final resolved = resolveAppearance(
        global: global,
        room: const RoomAppearance(accentHue: 25),
      );
      expect(resolved.hasRoomOverride, isTrue);
      expect(resolved.hasRoomPreset, isFalse);
    });

    test('without a room override the global values are used', () {
      final resolved = resolveAppearance(global: global);
      expect(resolved.preset, 'default');
      expect(resolved.accentHue, 268);
      expect(resolved.hasRoomOverride, isFalse);
      expect(resolved.hasRoomPreset, isFalse);
    });
  });

  group('BubbleCorners', () {
    test('tail never exceeds the radius', () {
      expect(BubbleCorners.sharp.tail, 6);
      expect(BubbleCorners.standard.tail, 6);
      expect(BubbleCorners.round.tail, 6);
    });

    test('bubbleRadius follows the corners and mirrors in RTL', () {
      final round = bubbleRadius(
        outgoing: true,
        tail: true,
        corners: BubbleCorners.round,
      );
      expect(round.topStart, const Radius.circular(26));
      expect(round.bottomEnd, const Radius.circular(6));
      final sharp = bubbleRadius(
        outgoing: false,
        tail: true,
        corners: BubbleCorners.sharp,
      );
      expect(sharp.topEnd, const Radius.circular(10));
      expect(sharp.bottomStart, const Radius.circular(6));
      expect(
        round.resolve(TextDirection.rtl).bottomLeft,
        const Radius.circular(6),
      );
    });

    test('the default corners keep the 20 px DESIGN radius', () {
      final standard = bubbleRadius(outgoing: false, tail: false);
      expect(standard.topStart, const Radius.circular(20));
    });
  });
}
