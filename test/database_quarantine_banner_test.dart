// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_quarantine_notice.dart';
import 'package:fluffychat/widgets/database_quarantine_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) =>
      const DatabaseQuarantineBanner(child: Scaffold(body: Placeholder()));
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _taps = 0;

  @override
  Widget build(BuildContext context) => Material(
    child: TextButton(
      onPressed: () => setState(() => _taps++),
      child: Text('tap $_taps'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: _Host(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no banner without a quarantine', (tester) async {
    await pumpHost(tester);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('the banner says what happened and what it means', (
    tester,
  ) async {
    await markDatabaseQuarantined('a');
    await pumpHost(tester);

    expect(find.byType(MaterialBanner), findsOneWidget);
    final text = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(MaterialBanner),
            matching: find.byType(Text).first,
          ),
        )
        .data!;
    expect(text, contains('damaged'));
    expect(text, contains('moved aside'));
    expect(text, contains('not deleted'));
    expect(text, contains('syncing again'));
    expect(text, contains('key backup'));
  });

  testWidgets('closing dismisses it for good', (tester) async {
    await markDatabaseQuarantined('a');
    await pumpHost(tester);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
    expect(hasDatabaseQuarantineNotice, isFalse);
    await pumpHost(tester);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('hiding the banner keeps the state of the content', (
    tester,
  ) async {
    await markDatabaseQuarantined('a');
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: DatabaseQuarantineBanner(child: _Counter()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('tap 0'));
    await tester.pump();
    expect(find.text('tap 1'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('tap 1'), findsOneWidget);
  });

  testGoldens('DatabaseQuarantineBanner', (tester) async {
    await markDatabaseQuarantined('a');
    await expectGoldenVariants(
      tester,
      'database_quarantine_banner',
      const _Host(),
      size: const Size(400, 400),
    );
  });

  testWidgets('a new quarantine shows it again', (tester) async {
    await markDatabaseQuarantined('a');
    await dismissDatabaseQuarantineNotice();
    await markDatabaseQuarantined('a');

    await pumpHost(tester);

    expect(find.byType(MaterialBanner), findsOneWidget);
  });
}
