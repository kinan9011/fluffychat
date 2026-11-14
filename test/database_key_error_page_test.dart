// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/database_key_error/database_key_error_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var retries = 0;
  var resets = 0;

  setUp(() async {
    retries = 0;
    resets = 0;
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      DatabaseKeyErrorPage.app(
        onRetry: () => retries++,
        onReset: () async => resets++,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed open explains storage and other copies of the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      DatabaseKeyErrorPage.app(
        onRetry: () => retries++,
        onReset: () async => resets++,
        keyProblem: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('low on storage'), findsOne);
    expect(find.textContaining('Nothing was deleted'), findsOne);
    expect(find.textContaining('keyring'), findsNothing);
  });

  testWidgets('a key problem still explains the keyring', (tester) async {
    await pumpPage(tester);

    expect(find.textContaining('keyring'), findsOne);
    expect(find.textContaining('low on storage'), findsNothing);
  });

  testWidgets('shows the error and retries without deleting anything', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text("Your local data can't be opened right now"), findsOne);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(retries, 1);
    expect(resets, 0);
  });

  testWidgets('reset needs a confirmation and can be cancelled', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Reset local data and sign in again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This signs you out of all accounts'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);

    await tester.tap(find.text('Reset local data and sign in again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset local data and sign in again').last);
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(retries, 0);
  });

  testWidgets('a running reset disables both buttons and shows progress', (
    tester,
  ) async {
    final completer = Completer<void>();
    var resetCalls = 0;
    await tester.pumpWidget(
      DatabaseKeyErrorPage.app(
        onRetry: () => retries++,
        onReset: () {
          resetCalls++;
          return completer.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset local data and sign in again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset local data and sign in again').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsOne);
    expect(find.text('Deleting local data…'), findsOne);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    await tester.tap(
      find.text('Reset local data and sign in again'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(resetCalls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failing reset enables the buttons again', (tester) async {
    await tester.pumpWidget(
      DatabaseKeyErrorPage.app(
        onRetry: () => retries++,
        onReset: () async => throw StateError('x'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset local data and sign in again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset local data and sign in again').last);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
