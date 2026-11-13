// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final launched = <String>[];

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
              return true;
            }
            return true;
          },
        );
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return context;
  }

  testWidgets('blocked schemes are never launched', (tester) async {
    final context = await pumpHost(tester);
    for (final url in [
      'file:///etc/passwd',
      'intent://x#Intent;scheme=a;end',
      'javascript:alert(1)',
      'content://provider/x',
      'data:text/html,hi',
      'android-app://com.example',
    ]) {
      ScaffoldMessenger.of(context).clearSnackBars();
      await UrlLauncher(context, url).launchUrl();
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing, reason: url);
      expect(find.textContaining(url), findsOneWidget, reason: url);
    }
    expect(launched, isEmpty);
  });

  testWidgets('the blocked link snackbar shortens very long urls', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    final url = 'data:text/plain,${'a' * 100000}';
    await UrlLauncher(context, url).launchUrl();
    await tester.pump();

    final text = tester.widget<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    );
    expect(text.data!.length, lessThan(400));
    expect(text.data, endsWith('…'));
    expect(launched, isEmpty);
  });

  testWidgets('geo links are rewritten, not launched raw', (tester) async {
    final context = await pumpHost(tester);
    await UrlLauncher(context, 'geo:52.5,13.4').launchUrl();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(launched, hasLength(1));
    expect(launched.single, isNot(startsWith('geo:')));
    expect(launched.single, contains('52.5'));
    expect(launched.single, contains('13.4'));
  });

  testWidgets('a link name differing from the url asks before opening', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    const url = 'https://example.org/real';
    final future = UrlLauncher(
      context,
      url,
      'https://trusted.example',
    ).launchUrl();
    await tester.pumpAndSettle();
    expect(find.text(url), findsOneWidget);
    expect(launched, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await future;
    expect(launched, isEmpty);

    final second = UrlLauncher(context, url, 'click here').launchUrl();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await second;
    expect(launched, [url]);
  });

  testWidgets('matrix links stay on the in-app flow', (tester) async {
    final context = await pumpHost(tester);
    for (final url in [
      'https://matrix.to/#/#room:example.org',
      'matrix:r/room:example.org',
      '#room:example.org',
    ]) {
      // The in-app flow needs the Matrix widget, which this host lacks:
      // reaching it proves the policy did not intercept the link.
      await expectLater(
        UrlLauncher(context, url).launchUrl(),
        throwsA(isA<ProviderNotFoundException>()),
        reason: url,
      );
    }
    expect(launched, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('custom scheme asks first and shows the full url', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    const url = 'custom-app://do/something?token=abc';
    final future = UrlLauncher(context, url).launchUrl();
    await tester.pumpAndSettle();
    expect(find.textContaining(url), findsOneWidget);
    expect(launched, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await future;
    expect(launched, isEmpty);
  });

  testWidgets('custom scheme is launched after confirmation', (tester) async {
    final context = await pumpHost(tester);
    const url = 'custom-app://do/something';
    final future = UrlLauncher(context, url).launchUrl();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await future;
    expect(launched, [url]);
  });

  testWidgets('plain https and mailto/tel launch without a dialog', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    for (final url in [
      'https://example.org/a',
      'mailto:a@example.org',
      'tel:+4912345',
    ]) {
      final future = UrlLauncher(context, url).launchUrl();
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      await future;
    }
    expect(launched, [
      'https://example.org/a',
      'mailto:a@example.org',
      'tel:+4912345',
    ]);
  });
}
