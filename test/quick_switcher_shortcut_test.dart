// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  String path() => FluffyChatApp.router.routeInformationProvider.value.uri.path;

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await harness.settle(tester, rounds: 3);
  }

  testWidgets('Ctrl+K opens the search from the chat list', (tester) async {
    await harness.open(tester, path: '/rooms');
    expect(path(), '/rooms');
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(path(), '/rooms/search');
    await harness.finish(tester);
  });

  testWidgets('Ctrl+K also works inside a chat, over the composer', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/${harness.room.id}');
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(path(), '/rooms/search');
    await harness.finish(tester);
  });

  testWidgets('on macOS it is Cmd+K and Ctrl+K does nothing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await harness.open(tester, path: '/rooms');
      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyK,
      );
      expect(path(), '/rooms');
      await chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyK);
      expect(path(), '/rooms/search');
      await harness.finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('K alone does not open anything', (tester) async {
    await harness.open(tester, path: '/rooms');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await harness.settle(tester, rounds: 3);
    expect(path(), '/rooms');
    await harness.finish(tester);
  });
}
