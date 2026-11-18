// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

extension type FluffyChatTester(WidgetTester tester) {
  static int _printCounter = 1;

  void _print(String message) {
    debugPrint(
      '[INTEGRATION TEST] ${DateTime.now().toIso8601String()} | Step ${_printCounter++} -  $message',
    );
  }

  Future<bool> isVisible(
    Object object, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final end = DateTime.now().add(timeout);
    while (object.toFinder().evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        return false;
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    return true;
  }

  Future<void> waitFor(
    Object object, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _print('👀 Waiting for "$object" (${timeout.inSeconds}s)');
    final end = DateTime.now().add(timeout);
    while (object.toFinder().evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw Exception('⏱️ Timed out waiting for "$object"!');
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> waitForGone(
    Object object, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _print('👀 Waiting for "$object" to disappear (${timeout.inSeconds}s)');
    final end = DateTime.now().add(timeout);
    while (object.toFinder().evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw Exception(
          '⏱️ "$object" is still there after ${timeout.inSeconds}s!',
        );
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<Finder> _ensureVisible(Object object, {int? index}) async {
    var finder = object.toFinder();
    if (finder.evaluate().isEmpty) await waitFor(object);

    if (finder.evaluate().length > 1) {
      if (index == null) {
        throw Exception(
          '⚠️ Found ${finder.evaluate().length} "$object" objects. Please specify an index!',
        );
      }
      if (finder.evaluate().length <= index) {
        throw Exception(
          '⚠️ Found ${finder.evaluate().length} "$object" objects. So index $index does not exist!',
        );
      }
      finder = finder.at(index);
    }
    return finder;
  }

  Future<void> tapOn(
    Object object, {
    int? index,
    bool pumpAndSettle = true,
  }) async {
    final finder = await _ensureVisible(object, index: index);

    _print('👆 Tapping on "$object"');
    await tester.tap(finder);
    if (pumpAndSettle) await tester.pumpAndSettle();
  }

  /// Opening a menu or sheet on a long press makes the Navigator cancel the
  /// pressed pointer. The live binding drops that cancel unless device events
  /// propagate, which leaves the pressed widget's recognizers stuck on the old
  /// pointer (every later tap or long press on it is dead). A phone delivers
  /// the cancel, so let it through here.
  Future<void> longPressOn(Object object, {int? index}) async {
    final finder = await _ensureVisible(object, index: index);

    _print('👆 Long pressing on "$object"');
    final binding = tester.binding;
    binding.shouldPropagateDevicePointerEvents = true;
    try {
      await tester.longPress(finder);
      await tester.pumpAndSettle();
    } finally {
      binding.shouldPropagateDevicePointerEvents = false;
    }
  }

  Future<void> goBack() => tapOn(find.byTooltip('Back'));

  Future<void> enterText(
    Object object,
    String text, {
    int? index,
    bool pumpAndSettle = true,
  }) async {
    final finder = await _ensureVisible(object, index: index);

    _print('⌨️ Enter "$text" into "$object"');
    await tester.enterText(finder, text);
    FocusManager.instance.primaryFocus?.unfocus();
    if (pumpAndSettle) await tester.pumpAndSettle();
  }

  Future<void> scrollUntilVisible(
    Object object, {
    int? index,
    Object? scrollable,
  }) async {
    _print('📜 Scrolling to "$object"');
    await tester.scrollUntilVisible(
      object.toFinder(),
      500.0,
      scrollable: scrollable?.toFinder() ?? find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }
}

extension on Object {
  Finder toFinder() => switch (this) {
    final Finder finder => finder,
    final String string => find.text(string),
    final Key key => find.byKey(key),
    final IconData icon => find.byIcon(icon),
    final Type type => find.byType(type),
    final Widget widget => find.byWidget(widget),
    _ => throw Exception('Unsupported finder type: $runtimeType'),
  };
}

extension StartTest on WidgetTester {
  Future<FluffyChatTester> startFluffyChatTest() async {
    // The test binding resets the lifecycle state for every test, but the app
    // only sends read markers while it is resumed.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    app.main(['integration_test']);
    // Every flow starts a new app with new clients. The clients of the flow
    // before keep syncing with a token that a logout revoked and log
    // M_UNKNOWN_TOKEN, so each flow disposes its own clients when it ends.
    addTearDown(() async {
      final matrix = find.byType(Matrix);
      if (matrix.evaluate().isEmpty) return;
      final clients = state<MatrixState>(matrix).widget.clients.toList();
      for (final client in clients) {
        try {
          await client.dispose();
        } catch (_) {}
      }
    });

    return FluffyChatTester(this);
  }
}
