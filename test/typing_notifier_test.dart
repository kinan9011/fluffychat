// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/pages/chat/typing_notifier.dart';

void main() {
  const idle = Duration(milliseconds: 40);
  late List<bool> sent;
  late bool enabled;
  late TypingNotifier notifier;

  Future<void> wait([int factor = 3]) => Future<void>.delayed(idle * factor);

  setUp(() {
    sent = [];
    enabled = true;
    notifier = TypingNotifier(
      send: (typing, {timeoutMs}) async => sent.add(typing),
      enabled: () => enabled,
      idle: idle,
      timeout: const Duration(seconds: 30),
    );
  });

  tearDown(() => notifier.dispose());

  test('disabled: nothing is ever sent', () async {
    enabled = false;
    for (var i = 0; i < 100; i++) {
      notifier.onTextChanged();
    }
    notifier.stop();
    await wait();
    expect(sent, isEmpty);
    expect(notifier.isTyping, isFalse);
  });

  test('a burst sends one true and one false after the idle time', () async {
    for (var i = 0; i < 10; i++) {
      notifier.onTextChanged();
    }
    expect(sent, [true]);
    expect(notifier.isTyping, isTrue);
    await wait();
    expect(sent, [true, false]);
    expect(notifier.isTyping, isFalse);
  });

  test('stop sends false once, a second stop sends nothing', () {
    notifier.onTextChanged();
    notifier.stop();
    notifier.stop();
    expect(sent, [true, false]);
  });

  test('stop without typing sends nothing', () {
    notifier.stop();
    expect(sent, isEmpty);
  });

  test('turned off while typing: one false, never another true', () async {
    notifier.onTextChanged();
    enabled = false;
    notifier.onTextChanged();
    notifier.onTextChanged();
    expect(sent, [true, false]);
    await wait();
    expect(sent, [true, false]);
  });

  test('dispose cancels the idle timer', () async {
    notifier.onTextChanged();
    notifier.dispose();
    await wait();
    expect(sent, [true]);
  });
}
