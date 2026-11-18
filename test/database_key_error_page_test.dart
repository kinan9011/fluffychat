// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/database_key_error/database_key_error_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var retries = 0;
  var resets = 0;
  var asides = 0;

  setUp(() async {
    retries = 0;
    resets = 0;
    asides = 0;
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      DatabaseKeyErrorPage.app(
        onRetry: () => retries++,
        onReset: () async {
          resets++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsidePage(
    WidgetTester tester, {
    Future<bool> Function()? onSetAside,
    Future<bool> Function()? onReset,
    bool resetMayRemovePin = false,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            Directionality(textDirection: textDirection, child: child!),
        home: DatabaseKeyErrorPage(
          onRetry: () => retries++,
          onReset:
              onReset ??
              () async {
                resets++;
                return true;
              },
          onSetAside:
              onSetAside ??
              () async {
                asides++;
                return true;
              },
          resetMayRemovePin: resetMayRemovePin,
          keyProblem: false,
        ),
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
        onReset: () async {
          resets++;
          return true;
        },
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
          return completer.future.then((_) => true);
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

  const asideLabel = "Move this account's data aside";
  const resetLabel = 'Reset local data and sign in again';

  testWidgets('without a callback there is no set-aside button (P1)', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text(asideLabel), findsNothing);
  });

  testWidgets('set-aside asks first, in a destructive-style dialog, and can '
      'be cancelled (P2)', (tester) async {
    await pumpAsidePage(tester);

    await tester.tap(find.text(asideLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('moved aside, not deleted'), findsOne);
    final okButton = find.byKey(const Key('ok_cancel_alert_dialog_ok_button'));
    final theme = Theme.of(tester.element(okButton));
    final ok = find.descendant(of: okButton, matching: find.byType(Text));
    expect(tester.widget<Text>(ok).style?.color, theme.colorScheme.error);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(asides, 0);
  });

  testWidgets('a confirmed set-aside runs once and is busy meanwhile (P3)', (
    tester,
  ) async {
    final completer = Completer<bool>();
    var calls = 0;
    await pumpAsidePage(
      tester,
      onSetAside: () {
        calls++;
        return completer.future;
      },
    );

    await tester.tap(find.text(asideLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(asideLabel).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(calls, 1);
    expect(find.text('Moving local data aside…'), findsOne);
    expect(find.text('Deleting local data…'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    for (final button in tester.widgetList<TextButton>(
      find.byType(TextButton),
    )) {
      expect(button.onPressed, isNull);
    }
    completer.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed set-aside says so and enables the buttons (P4)', (
    tester,
  ) async {
    await pumpAsidePage(tester, onSetAside: () async => false);

    await tester.tap(find.text(asideLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(asideLabel).last);
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't be moved aside"), findsOne);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a throwing set-aside is reported the same way', (tester) async {
    await pumpAsidePage(tester, onSetAside: () async => throw StateError('x'));

    await tester.tap(find.text(asideLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(asideLabel).last);
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't be moved aside"), findsOne);
  });

  testWidgets('an incomplete reset is reported and Retry still works (P5)', (
    tester,
  ) async {
    await pumpAsidePage(tester, onReset: () async => false);

    await tester.tap(find.text(resetLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(resetLabel).last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Some local data couldn't be removed"),
      findsOne,
    );
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('a throwing reset is reported as incomplete', (tester) async {
    await pumpAsidePage(tester, onReset: () async => throw StateError('x'));

    await tester.tap(find.text(resetLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(resetLabel).last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Some local data couldn't be removed"),
      findsOne,
    );
  });

  testWidgets('the reset confirmation warns about the PIN only when it can '
      'happen (P9)', (tester) async {
    await pumpAsidePage(tester, resetMayRemovePin: true);
    await tester.tap(find.text(resetLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('app lock PIN'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await pumpAsidePage(tester);
    await tester.tap(find.text(resetLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('app lock PIN'), findsNothing);
  });

  testWidgets('RTL layout shows all three actions without overflow (P6)', (
    tester,
  ) async {
    await pumpAsidePage(tester, textDirection: TextDirection.rtl);

    expect(tester.takeException(), isNull);
    expect(find.byType(FilledButton), findsOne);
    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('every action is at least 48 high and labelled (P7)', (
    tester,
  ) async {
    await pumpAsidePage(tester);

    for (final finder in [
      find.byType(FilledButton),
      find.byType(TextButton).first,
      find.byType(TextButton).last,
    ]) {
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }
    expect(
      find.ancestor(
        of: find.text(asideLabel),
        matching: find.byType(TextButton),
      ),
      findsOne,
    );
  });

  testWidgets('a 320x568 screen at text scale 1.3 shows everything and '
      'scrolls (P8)', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAsidePage(tester, resetMayRemovePin: true);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(resetLabel));
    await tester.ensureVisible(find.text(asideLabel));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(asideLabel));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ok_cancel_alert_dialog_ok_button')), findsOne);
  });
}
