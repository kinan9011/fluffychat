// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/chat/waveform.dart';

void main() {
  test('always 26 bars between 0 and 1', () {
    for (final length in [1, 10, 26, 100, 1024]) {
      final bars = resampleWaveform(List.generate(length, (i) => i % 1025));
      expect(bars.length, 26, reason: '$length');
      expect(bars.every((bar) => bar >= 0 && bar <= 1), isTrue);
    }
  });

  test('no waveform gives a flat placeholder', () {
    expect(resampleWaveform(null), List.filled(26, 0.25));
    expect(resampleWaveform([]), List.filled(26, 0.25));
  });

  test('values are clamped', () {
    final bars = resampleWaveform([-5, 1 << 40, 1 << 62, -1 << 60]);
    expect(bars.every((bar) => bar >= 0 && bar <= 1), isTrue);
    expect(bars.reduce((a, b) => a > b ? a : b), 1);
  });

  test('only the first 1024 entries are read', () {
    final huge = [...List.filled(1024, 0), ...List.filled(100000, 1024)];
    expect(resampleWaveform(huge).every((bar) => bar == 0), isTrue);
  });

  test('a bucket takes the loudest value', () {
    final bars = resampleWaveform([0, 1024, 0, 0], bars: 2);
    expect(bars, [1.0, 0.0]);
  });

  test('senders that stop at 256 fill the bar height', () {
    expect(resampleWaveform([256, 0], bars: 2), [1.0, 0.0]);
    expect(resampleWaveform([128, 0], bars: 2), [0.5, 0.0]);
    expect(resampleWaveform([512, 0], bars: 2), [0.5, 0.0]);
  });

  test('a million entries are resampled without walking them all', () {
    final stopwatch = Stopwatch()..start();
    resampleWaveform(List.filled(1000000, 100));
    expect(stopwatch.elapsedMilliseconds, lessThan(200));
  });
}
