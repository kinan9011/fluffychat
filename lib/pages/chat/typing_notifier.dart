// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

/// Typing notifications for the composer. [enabled] is read on every call, so
/// turning the setting off stops the next notification at once.
class TypingNotifier {
  TypingNotifier({
    required this.send,
    required this.enabled,
    this.idle = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 30),
  });

  final Future<void> Function(bool typing, {int? timeoutMs}) send;
  final bool Function() enabled;
  final Duration idle;
  final Duration timeout;

  Timer? _idleTimer;
  Timer? _timeoutTimer;
  bool _typing = false;

  bool get isTyping => _typing;

  void onTextChanged() {
    if (!enabled()) return stop();
    _idleTimer?.cancel();
    _idleTimer = Timer(idle, () {
      _idleTimer = null;
      _typing = false;
      unawaited(send(false));
    });
    _timeoutTimer ??= Timer(timeout, () {
      _timeoutTimer = null;
      _typing = false;
    });
    if (_typing) return;
    _typing = true;
    unawaited(send(true, timeoutMs: timeout.inMilliseconds));
  }

  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_typing) return;
    _typing = false;
    unawaited(send(false));
  }

  void dispose() {
    _idleTimer?.cancel();
    _timeoutTimer?.cancel();
    _idleTimer = null;
    _timeoutTimer = null;
  }
}
