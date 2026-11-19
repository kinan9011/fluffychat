// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/calls/calls_page.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/settings_appearance/settings_appearance.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/layouts/app_nav_rail.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/call_support_fakes.dart';
import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
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
    client = await prepareTestClient();
    client.backgroundSync = false;
  });

  String joinedId() {
    final room = client.rooms.firstWhere(
      (room) => room.membership == Membership.join,
    );
    room.prev_batch = null;
    return room.id;
  }

  setUp(() {
    MatrixState.accountHooks = (_, _, _) async {};
    FakeCallCapabilities(pure: true).install();
  });

  tearDown(() async {
    FakeCallCapabilities.uninstall();
    MatrixState.accountHooks = MatrixState.defaultAccountHooks;
    await AppSettings.displayChatDetailsColumn.setItem(false);
  });

  Future<void> pump(WidgetTester tester, double width, String location) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    FluffyChatApp.router.go(location);
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 6; i++) {
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

  testWidgets('1280 px: chat list left, chat page right', (tester) async {
    await pump(tester, 1280, '/rooms/${joinedId()}');
    expect(find.byType(ChatList), findsOneWidget);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(
      tester.getSize(find.byType(ChatList)).width,
      FluffyThemes.listColumnWidth,
    );
    await finish(tester);
  });

  testWidgets('1280 px: the details panel is 340 px wide when switched on', (
    tester,
  ) async {
    await AppSettings.displayChatDetailsColumn.setItem(true);
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    await pump(tester, 1280, '/rooms/${joinedId()}');
    final panel = find.ancestor(
      of: find.byType(ChatDetails),
      matching: find.byType(Container),
    );
    expect(tester.getSize(panel.first).width, FluffyThemes.detailsPanelWidth);
    expect(FluffyThemes.detailsPanelWidth, 340);
    await finish(tester);
  });

  testWidgets('1279 px: no details panel even when switched on', (
    tester,
  ) async {
    await AppSettings.displayChatDetailsColumn.setItem(true);
    await pump(tester, 1279, '/rooms/${joinedId()}');
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(ChatDetails), findsNothing);
    await finish(tester);
  });

  testWidgets('900 px: settings left, appearance page right', (tester) async {
    await pump(tester, 900, '/settings/appearance');
    expect(find.byType(Settings), findsOneWidget);
    expect(find.byType(SettingsAppearance), findsOneWidget);
    expect(find.byType(AppNavRail), findsOneWidget);
    await finish(tester);
  });

  testWidgets('600 px: calls in the left column under the tab strip', (
    tester,
  ) async {
    await pump(tester, 600, '/calls');
    expect(find.byType(CallsPage), findsOneWidget);
    expect(find.byType(AppTabStrip), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(CallsPage)).dx,
      lessThan(FluffyThemes.listColumnWidth),
    );
    await finish(tester);
  });
}
