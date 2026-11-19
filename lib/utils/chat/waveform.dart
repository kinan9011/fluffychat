// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:odango/config/design_constants.dart';

const _maxInput = 1024;

/// A voice message waveform is sender controlled: read at most [_maxInput]
/// entries, clamp them, and resample to a fixed number of bars in 0..1.
List<double> resampleWaveform(
  List<int>? waveform, {
  int bars = AppChat.waveformBars,
}) {
  if (waveform == null || waveform.isEmpty) {
    return List.filled(bars, 0.25);
  }
  // Newer versions of MSC3246 define 256 as the maximum, older ones 1024:
  // Element X sends 1024, Mautrix WhatsApp 256.
  final input = waveform.take(_maxInput).map((v) => v.clamp(0, 1024)).toList();
  final scale = input.any((value) => value > 256) ? 1024 : 256;
  return List.generate(bars, (i) {
    final start = (i * input.length / bars).floor();
    final end = math.max(start + 1, ((i + 1) * input.length / bars).ceil());
    final bucket = input.sublist(start, math.min(end, input.length));
    return bucket.reduce(math.max) / scale;
  });
}
