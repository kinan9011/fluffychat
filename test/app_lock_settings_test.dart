// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/main.dart';
import 'package:odango/pages/app_lock_unavailable/app_lock_unavailable_page.dart';
import 'package:odango/utils/app_lock_settings.dart';
import 'package:odango/utils/secure_storage.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'utils/test_client.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _mockStorage(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('readAppLockSettings', () {
    test('reads the pin and the biometrics flag', () async {
      _mockStorage((call) async {
        final key = (call.arguments as Map)['key'];
        return switch (key) {
          'com.swovo.odango.app_lock' => '1234',
          'com.swovo.odango.use_biometrics' => 'true',
          _ => null,
        };
      });
      final read = await readAppLockSettings(createSecureStorage());
      expect(read, (pincode: '1234', useBiometrics: true, failed: false));
    });

    test('no pin set is not a failure', () async {
      _mockStorage((_) async => null);
      final read = await readAppLockSettings(createSecureStorage());
      expect(read, (pincode: null, useBiometrics: false, failed: false));
    });

    test('a keystore error is reported as a failure, not as no pin', () async {
      _mockStorage((_) async => throw PlatformException(code: 'keystore'));
      final read = await readAppLockSettings(createSecureStorage());
      expect(read.failed, isTrue);
      expect(read.pincode, isNull);
    });
  });

  group('appLockMustBlock', () {
    const failed = (pincode: null, useBiometrics: false, failed: true);
    const fine = (pincode: null, useBiometrics: false, failed: false);

    test('a failed read blocks a signed-in app', () {
      expect(appLockMustBlock(failed, signedIn: true), isTrue);
    });

    test('nothing to protect without a signed-in account', () {
      expect(appLockMustBlock(failed, signedIn: false), isFalse);
    });

    test('a readable state never blocks', () {
      expect(appLockMustBlock(fine, signedIn: true), isFalse);
    });
  });

  testWidgets('the blocking page offers only a retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    var retried = 0;
    await tester.pumpWidget(
      AppLockUnavailablePage.app(onRetry: () async => retried++),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Secure storage is not answering'), findsOne);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('two quick taps start one retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    final gate = Completer<void>();
    var retried = 0;
    await tester.pumpWidget(
      AppLockUnavailablePage.app(
        onRetry: () {
          retried++;
          return gate.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(retried, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  group('startGui', () {
    late Client signedIn;
    late Client signedOut;

    setUpAll(() async {
      signedIn = await prepareTestClient(clientName: 'LockSignedIn');
      signedOut = Client(
        'LockSignedOut',
        httpClient: FakeMatrixApi(),
        database: await MatrixSdkDatabase.init(
          'locksignedout',
          database: await databaseFactoryFfi.openDatabase(
            ':memory:',
            options: OpenDatabaseOptions(singleInstance: false),
          ),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
    });

    testWidgets(
      'an unreadable PIN with an account shows the page, not the app',
      (tester) async {
        final shown = <Widget>[];
        final prefs = await SharedPreferences.getInstance();
        await tester.runAsync(
          () => startGui(
            [signedIn],
            prefs,
            readLock: () async =>
                (pincode: null, useBiometrics: false, failed: true),
            show: shown.add,
          ),
        );
        expect(shown, hasLength(1));
        await tester.pumpWidget(shown.single);
        await tester.pumpAndSettle();
        expect(find.byType(AppLockUnavailablePage), findsOneWidget);
        expect(find.byType(FluffyChatApp), findsNothing);
      },
    );

    testWidgets('retrying with a working keystore starts the app', (
      tester,
    ) async {
      final shown = <Widget>[];
      final prefs = await SharedPreferences.getInstance();
      var failing = true;
      await tester.runAsync(
        () => startGui(
          [signedIn],
          prefs,
          readLock: () async => (
            pincode: failing ? null : '1234',
            useBiometrics: false,
            failed: failing,
          ),
          show: shown.add,
        ),
      );
      failing = false;
      await tester.pumpWidget(shown.single);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byType(FilledButton));
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      expect(shown.last, isA<FluffyChatApp>());
    });

    testWidgets('an unreadable PIN without an account is not a lock-out', (
      tester,
    ) async {
      final shown = <Widget>[];
      final prefs = await SharedPreferences.getInstance();
      await tester.runAsync(
        () => startGui(
          [signedOut],
          prefs,
          readLock: () async =>
              (pincode: null, useBiometrics: false, failed: true),
          show: shown.add,
        ),
      );
      expect(shown.single, isA<FluffyChatApp>());
    });
  });
}
