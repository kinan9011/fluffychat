// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:fluffychat/pages/chat_list/key_backup_banner.dart';
import 'package:fluffychat/utils/crypto_identity.dart' as crypto_identity;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

class _BackupStub extends StatefulWidget {
  const _BackupStub();

  @override
  State<_BackupStub> createState() => _BackupStubState();
}

class _BackupStubState extends State<_BackupStub> {
  @override
  void dispose() {
    crypto_identity.cryptoIdentityRevision.value++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => Navigator.of(context).pop(),
    child: const Text('close backup'),
  );
}

void main() {
  late Client first;
  late Client second;

  setUpAll(() async {
    first = await prepareTestClient();
    second = await prepareTestClient(clientName: 'Second banner client');
  });

  setUp(KeyBackupBanner.resetForTest);

  tearDown(() {
    crypto_identity.loadCryptoIdentityConnected = noCryptoIdentity;
  });

  var calls = <Client>[];

  void seam(Future<bool?> Function(Client) body) {
    calls = [];
    crypto_identity.loadCryptoIdentityConnected = (client) {
      calls.add(client);
      return body(client);
    };
  }

  Future<GoRouter> pump(WidgetTester tester, {Client? client}) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) =>
              Scaffold(body: KeyBackupBanner(client: client ?? first)),
        ),
        GoRoute(path: '/backup', builder: (_, _) => const _BackupStub()),
      ],
    );
    addTearDown(router.dispose);
    await pumpGoldenWidget(
      tester,
      Router.withConfig(config: router),
      size: const Size(400, 300),
    );
    await tester.pump();
    return router;
  }

  testWidgets('a missing key backup shows the banner', (tester) async {
    seam((_) async => false);
    await pump(tester);
    expect(find.text('Back up your encryption keys'), findsOneWidget);
    expect(
      find.text('So you can read old messages on new devices'),
      findsOneWidget,
    );
    expect(find.text('Set up'), findsOneWidget);
  });

  testWidgets('the banner is announced to screen readers when it appears', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    seam((_) async => false);
    await pump(tester);
    final node = tester.getSemantics(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
    );
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  for (final value in [true, null]) {
    testWidgets('the state $value shows nothing', (tester) async {
      seam((_) async => value);
      await pump(tester);
      expect(find.text('Back up your encryption keys'), findsNothing);
    });
  }

  testWidgets('a failing check shows nothing and logs a fixed line', (
    tester,
  ) async {
    Logs().outputEvents.clear();
    seam((_) async => throw Exception('SENTINEL-KEY-STATE'));
    await pump(tester);
    expect(find.text('Back up your encryption keys'), findsNothing);
    final lines = Logs().outputEvents.where(
      (event) => event.title.contains('[KeyBackup]'),
    );
    expect(lines.single.title, '[KeyBackup] state check failed');
    for (final event in Logs().outputEvents) {
      expect('${event.exception}${event.title}', isNot(contains('SENTINEL')));
    }
  });

  testWidgets('Set up opens the backup page, closing it checks again', (
    tester,
  ) async {
    seam((_) async => false);
    final router = await pump(tester);
    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/backup',
    );
    expect(calls, hasLength(1));
    seam((_) async => true);
    await tester.tap(find.text('close backup'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1), reason: 'the second seam saw one call');
    expect(find.text('Back up your encryption keys'), findsNothing);
  });

  testWidgets('a screen reader reads the title once', (tester) async {
    final handle = tester.ensureSemantics();
    seam((_) async => false);
    await pump(tester);
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('Back up your encryption keys')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('read old messages on new devices')),
      findsOneWidget,
    );
    handle.dispose();
  });

  test('logging out forgets what was dismissed for that client', () {
    KeyBackupBanner.resetForTest();
    KeyBackupBanner.forget('nobody');
    final source = File('lib/widgets/matrix.dart').readAsStringSync();
    expect(source, contains('KeyBackupBanner.forget(name)'));
  });

  testWidgets('closing hides it for that client only', (tester) async {
    seam((_) async => false);
    await pump(tester);
    await tester.tap(find.byTooltip('Close key backup reminder'));
    await tester.pump();
    expect(find.text('Back up your encryption keys'), findsNothing);
    await pump(tester);
    expect(find.text('Back up your encryption keys'), findsNothing);
    await pump(tester, client: second);
    expect(find.text('Back up your encryption keys'), findsOneWidget);
  });

  testWidgets('a slow answer for the previous client is ignored', (
    tester,
  ) async {
    final pending = <Client, Completer<bool?>>{};
    seam((client) => (pending[client] = Completer<bool?>()).future);
    final holder = ValueNotifier<Client>(first);
    addTearDown(holder.dispose);
    await pumpGoldenWidget(
      tester,
      ValueListenableBuilder<Client>(
        valueListenable: holder,
        builder: (context, client, _) =>
            Scaffold(body: KeyBackupBanner(client: client)),
      ),
      size: const Size(400, 300),
    );
    holder.value = second;
    await tester.pump();
    pending[second]!.complete(true);
    await tester.pump();
    pending[first]!.complete(false);
    await tester.pump();
    expect(find.text('Back up your encryption keys'), findsNothing);
  });

  testWidgets('rebuilds and remounts do not ask again (once per session)', (
    tester,
  ) async {
    seam((_) async => false);
    await pump(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(calls, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(calls, hasLength(1), reason: 'same client, same session');
    expect(find.text('Back up your encryption keys'), findsOneWidget);
    await pump(tester, client: second);
    expect(calls, hasLength(2), reason: 'another client asks once');
  });

  testWidgets('targets are at least 44 and large text does not overflow', (
    tester,
  ) async {
    seam((_) async => false);
    await pump(tester);
    expect(
      tester.getSize(find.byTooltip('Close key backup reminder')).shortestSide,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.widgetWithText(InkWell, 'Set up')).height,
      greaterThanOrEqualTo(44),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Set up'), findsOneWidget);
  });

  testWidgets('goldens: light, dark and RTL', (tester) async {
    seam((_) async => false);
    await expectGoldenVariants(
      tester,
      'key_backup_banner',
      Align(
        alignment: Alignment.topCenter,
        child: KeyBackupBanner(client: first),
      ),
      size: const Size(400, 140),
    );
  });

  test('the backup page announces its closing', () {
    final source = File(
      'lib/pages/bootstrap/view_model/bootstrap_view_model.dart',
    ).readAsStringSync();
    expect(source, contains('cryptoIdentityRevision.value++'));
  });

  test('the banner only opens the backup page', () {
    final source = File(
      'lib/pages/chat_list/key_backup_banner.dart',
    ).readAsStringSync();
    expect(RegExp(r'context\.(push|go)\(').allMatches(source).length, 1);
    expect(source, contains("context.push('/backup')"));
  });
}
