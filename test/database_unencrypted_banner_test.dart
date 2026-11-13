// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/widgets/database_unencrypted_warning.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';

class _BannerHost extends StatefulWidget {
  const _BannerHost();

  @override
  State<_BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<_BannerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showDatabaseUnencryptedBanner(context),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const _BannerHost()),
    GoRoute(
      path: '/settings/security',
      builder: (_, _) => const Text('security page'),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
    // a readable key resets the in-memory state left by earlier tests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'read' ? 'fake-password' : null,
        );
    await getDatabaseCipher();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: _router(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no banner while the database is encrypted', (tester) async {
    await pumpApp(tester);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('banner is shown when the database is unencrypted', (
    tester,
  ) async {
    await AppSettings.databaseUnencrypted.setItem(true);
    await pumpApp(tester);
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.text('Your local data is not encrypted'), findsOneWidget);
  });

  testWidgets('banner is shown even if persisting the flag failed', (
    tester,
  ) async {
    await tester.runAsync(
      () => getDatabaseCipher(
        markEncryption: ({required bool isEncrypted}) async =>
            throw StateError('prefs write failed'),
      ),
    );
    expect(AppSettings.databaseUnencrypted.value, isFalse);

    await pumpApp(tester);

    expect(find.byType(MaterialBanner), findsOneWidget);
  });

  testWidgets('close dismisses the banner and remembers it', (tester) async {
    await AppSettings.databaseUnencrypted.setItem(true);
    await pumpApp(tester);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
    expect(AppSettings.databaseUnencryptedNoticeDismissed.value, isTrue);
    await pumpApp(tester);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('security opens the security settings', (tester) async {
    await AppSettings.databaseUnencrypted.setItem(true);
    await pumpApp(tester);

    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();

    expect(find.text('security page'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testGoldens('DatabaseUnencryptedBanner', (tester) async {
    await AppSettings.databaseUnencrypted.setItem(true);
    await expectGoldenVariants(
      tester,
      'database_unencrypted_banner',
      InheritedGoRouter(goRouter: _router(), child: const _BannerHost()),
      size: const Size(400, 160),
    );
  });
}
