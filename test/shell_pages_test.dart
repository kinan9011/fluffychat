// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/calls/calls_page.dart';
import 'package:fluffychat/pages/profile/profile_page.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
  });

  Future<void> pumpApp(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(400, 800);
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
    await tester.pump(const Duration(milliseconds: 100));
    FluffyChatApp.router.go(location);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Requests go through a real database isolate (real time) while their
  /// continuations run on the fake clock, so alternate between both.
  Future<void> settleRequests(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  void pageTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        // lets the request timeouts of the opened pages expire
        await tester.pump(const Duration(seconds: 35));
      });

  group('Calls tab', () {
    pageTest('shows the empty state and the group call section', (
      tester,
    ) async {
      await pumpApp(tester, '/calls');
      expect(find.byType(CallsPage), findsOneWidget);
      expect(find.text('Ongoing group calls'), findsOneWidget);
      await settleRequests(tester);
      expect(
        find.text(
          "Your server isn't set up for group calls. One-to-one calls still work.",
        ),
        findsOneWidget,
      );
    });

    pageTest('loads the capabilities of the active account', (tester) async {
      await pumpApp(tester, '/calls');
      final matrix = tester.state<MatrixState>(find.byType(Matrix));
      await settleRequests(tester);
      expect(
        matrix.serverCapabilities.cached(client)[ServerFeature.groupCalls],
        isNot(FeatureSupport.unknown),
      );
    });
  });

  group('Profile tab', () {
    pageTest('shows the own MXID and the logged in accounts', (tester) async {
      await pumpApp(tester, '/profile');
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('@test:fakeServer.notExisting'), findsWidgets);
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      expect(find.text('My QR code'), findsOneWidget);
    });

    pageTest('copying the Matrix ID uses the clipboard and logs nothing', (
      tester,
    ) async {
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final logsBefore = Logs().outputEvents.length;
      await pumpApp(tester, '/profile');
      await tester.tap(find.text('Matrix ID'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(copied, ['@test:fakeServer.notExisting']);
      for (final event in Logs().outputEvents.skip(logsBefore)) {
        expect(event.title, isNot(contains('@test:fakeServer')));
        expect('${event.exception}', isNot(contains('@test:fakeServer')));
      }
    });
  });

  group('golden', () {
    for (final (page, location) in [
      (CallsPage, '/calls'),
      (ProfilePage, '/profile'),
    ]) {
      for (final variant in [
        (suffix: 'light', dark: false),
        (suffix: 'dark', dark: true),
      ]) {
        pageTest('$page ${variant.suffix}', (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = variant.dark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(() {
            tester.platformDispatcher.clearPlatformBrightnessTestValue();
          });
          await pumpApp(tester, location);
          await settleRequests(tester);
          await tester.loadAssets();
          await tester.pump();
          await expectLater(
            find.byType(page),
            matchesGoldenFile(
              'goldens/shell_${location.substring(1)}_${variant.suffix}.png',
            ),
          );
        });
      }
    }
  });
}
