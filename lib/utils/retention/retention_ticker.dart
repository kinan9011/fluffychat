// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:odango/utils/retention/retention_policy.dart';

/// One timer that calls [onExpire] when the next message of a room expires,
/// so the view can hide it. The wait is never shorter than [minWait], which
/// keeps a burst of expiries from turning into a tight loop.
class RetentionTicker {
  RetentionTicker({
    required this.onExpire,
    this.minWait = const Duration(seconds: 1),
  });

  final void Function() onExpire;
  final Duration minWait;
  Timer? _timer;

  /// Replaces the armed timer. Arms nothing without a [policy] or when no
  /// message of [events] expires within the look-ahead.
  void schedule(RetentionPolicy? policy, Iterable<Event> events) {
    _timer?.cancel();
    _timer = null;
    final now = DateTime.now();
    final next = policy?.nextExpiry(events, now);
    if (next == null) return;
    final wait = next.difference(now);
    _timer = Timer(wait < minWait ? minWait : wait, onExpire);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
