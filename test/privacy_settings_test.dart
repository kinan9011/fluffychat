// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/settings_security/privacy_toggles.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
  });

  Map<String, Object?> web(Map<String, Object?> config) =>
      filterPlatformConfiguration(config, PlatformConfigSource.web);
  Map<String, Object?> mdm(Map<String, Object?> config) =>
      filterPlatformConfiguration(config, PlatformConfigSource.mdm);

  group('config.json can only choose the more private value', () {
    test('sharing online status can only be switched off', () {
      expect(web({'shareOnlineStatus': true}), isEmpty);
      expect(web({'shareOnlineStatus': false}), {'shareOnlineStatus': false});
      expect(web({'shareOnlineStatus': 'false'}), isEmpty);
    });

    test('appearing offline can only be switched on', () {
      expect(web({'appearOffline': false}), isEmpty);
      expect(web({'appearOffline': true}), {'appearOffline': true});
    });

    test('typing and receipts keep their rule', () {
      expect(
        web({'sendTypingNotifications': true, 'sendPublicReadReceipts': true}),
        isEmpty,
      );
      expect(
        web({
          'sendTypingNotifications': false,
          'sendPublicReadReceipts': false,
        }),
        hasLength(2),
      );
    });
  });

  group('deployer configuration still decides the default', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
    });

    tearDown(
      () => AppSettings.applyPlatformConfiguration(
        null,
        PlatformConfigSource.mdm,
      ),
    );

    test(
      'MDM may set a less private default, the user value still wins',
      () async {
        AppSettings.applyPlatformConfiguration({
          'sendPublicReadReceipts': true,
          'sendTypingNotifications': true,
          'shareOnlineStatus': true,
          'appearOffline': false,
        }, PlatformConfigSource.mdm);
        expect(AppSettings.sendPublicReadReceipts.value, isTrue);
        expect(AppSettings.sendTypingNotifications.value, isTrue);
        expect(AppSettings.shareOnlineStatus.value, isTrue);
        await AppSettings.sendPublicReadReceipts.setItem(false);
        expect(AppSettings.sendPublicReadReceipts.value, isFalse);
      },
    );

    test('a web config cannot weaken the default', () {
      AppSettings.applyPlatformConfiguration({
        'sendPublicReadReceipts': true,
        'shareOnlineStatus': true,
      }, PlatformConfigSource.web);
      expect(AppSettings.sendPublicReadReceipts.value, isFalse);
      expect(AppSettings.shareOnlineStatus.value, isFalse);
    });

    test('MDM accepts every value for the four keys', () {
      for (final key in [
        'sendPublicReadReceipts',
        'sendTypingNotifications',
        'shareOnlineStatus',
        'appearOffline',
      ]) {
        expect(mdm({key: true}), {key: true});
        expect(mdm({key: false}), {key: false});
      }
    });
  });

  group('Security settings page', () {
    late Client client;

    setUpAll(() async {
      client = await prepareTestClient();
      client.backgroundSync = false;
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await AppSettings.store.clear();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        FluffyChatApp(
          clients: [client],
          store: prefs,
          appLockSettings: (pincode: null, useBiometrics: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      FluffyChatApp.router.go('/settings/security');
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('four toggles, all off, each writes its setting', (
      tester,
    ) async {
      await pump(tester);
      final titles = {
        "Show when I'm typing": AppSettings.sendTypingNotifications,
        'Send read receipts': AppSettings.sendPublicReadReceipts,
        'Show online status': AppSettings.shareOnlineStatus,
        'Appear offline': AppSettings.appearOffline,
      };
      for (final entry in titles.entries) {
        expect(find.text(entry.key), findsOneWidget, reason: entry.key);
        expect(entry.value.value, isFalse, reason: entry.key);
      }
      for (final entry in titles.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pump();
        expect(entry.value.value, isTrue, reason: entry.key);
      }
      expect(
        find.textContaining('still record what you\'ve read'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 35));
    });
  });

  testGoldens('PrivacyToggles', (tester) async {
    await expectGoldenVariants(
      tester,
      'privacy_toggles',
      const SingleChildScrollView(child: PrivacyToggles()),
      size: const Size(400, 460),
    );
  });
}
