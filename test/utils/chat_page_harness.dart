// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:http/http.dart' show BaseClient;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_client.dart';

/// The whole app on a fake server, opened on a chat. Shared by the conversation
/// widget tests.
class ChatPageHarness {
  ChatPageHarness({this.httpClient});

  /// A recording fake server for tests that assert on the requests.
  final BaseClient? httpClient;

  late Client client;

  Future<void> setUpAll() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
    client = await prepareTestClient(httpClient: httpClient);
    client.backgroundSync = false;
  }

  Room get room {
    final room = client.rooms.firstWhere(
      (room) => room.membership == Membership.join,
    );
    room.prev_batch = null;
    return room;
  }

  void setUp() {
    DraftStore.forget(client);
    MatrixState.accountHooks = (_, _, _) async {};
  }

  Future<void> tearDown() async {
    MatrixState.accountHooks = MatrixState.defaultAccountHooks;
    unawaited(DraftStore.of(client).remove(room.id));
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
    Brightness brightness = Brightness.light,
    Locale? locale,
    int highlightCount = 0,
  }) async {
    room.highlightCount = highlightCount;
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client],
        store: prefs,
        locale: locale,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    FluffyChatApp.router.go('/rooms/${room.id}');
    await settle(tester, rounds: locale == null ? 6 : 24);
    await tester.loadAssets();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  }
}
