// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:fluffychat/utils/oklch.dart';
import 'package:material_ui/material_ui.dart';

Color avatarColorForHue(double hue) => oklchColor(0.55, 0.12, hue);

extension StringColor on String {
  static const _maxHashedLength = 1024;

  /// Same value on every platform: integer-only rolling hash (djb2 with a
  /// prime modulus keeps every product below 2^53, so web matches the VM) over
  /// the UTF-8 bytes of at most [_maxHashedLength] characters of untrusted
  /// input.
  double get colorHue {
    var hash = 5381;
    for (final byte in utf8.encode(
      substring(0, math.min(length, _maxHashedLength)),
    )) {
      hash = (hash * 33 + byte) % 4294967291;
    }
    return (hash % 360).toDouble();
  }

  Color get avatarColor => avatarColorForHue(colorHue);

  Color nameColor(Brightness brightness) =>
      oklchColor(brightness == Brightness.dark ? 0.76 : 0.52, 0.14, colorHue);
}
