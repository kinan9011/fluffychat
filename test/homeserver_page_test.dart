// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/settings_homeserver/homeserver_details.dart';
import 'package:fluffychat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show MatrixSdkDatabase;

import 'utils/call_support_fakes.dart';
import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  final shared = <Map<Object?, Object?>>[];

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    FakeCallCapabilities.uninstall();
    await AppSettings.store.clear();
    api.clear();
    api.getOverrides.clear();
    api.notFound.clear();
    api.onRequest = null;
    shared.clear();
    await (harness.client.database as MatrixSdkDatabase)
        .clearCustomCacheObjects();
    api.getOverrides['/versions'] = {
      'versions': ['v1.1', 'v1.4'],
      'unstable_features': {
        'org.matrix.simplified_msc3575': true,
        'org.matrix.msc1763': false,
        'org.matrix.msc4140': false,
      },
    };
    api.getOverrides['/config'] = {'m.upload.size': 100000000};
    api.getOverrides['/matrix/server'] = {
      'm.server': 'federation.fakeserver.notexisting:8448',
    };
    api.getOverrides['/federation/v1/version'] = {
      'server': {'name': 'Synapse', 'version': '1.99.0'},
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async {
            if (call.method == 'share') {
              shared.add(Map<Object?, Object?>.from(call.arguments as Map));
            }
            return 'dev.fluttercommunity.plus/share/unavailable';
          },
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          null,
        );
    await harness.tearDown();
  });

  Future<void> openPage(
    WidgetTester tester, {
    double width = 400,
    double height = 1000,
  }) async {
    await harness.open(
      tester,
      path: '/settings/homeserver',
      width: width,
      height: height,
    );
    await harness.settle(tester, rounds: 8);
  }

  testWidgets('rows keep the mockup order, each with label and icon', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.byType(SettingsHomeserver), findsOneWidget);
    final order = [
      'Sliding sync',
      'Disappearing messages',
      'Sign in with QR',
      'Thread notifications',
      'Server-side scheduling',
      'Group calls',
    ];
    double? last;
    for (final title in order) {
      final y = tester.getTopLeft(find.text(title)).dy;
      if (last != null) expect(y, greaterThan(last), reason: title);
      last = y;
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('feature_slidingSync')),
        matching: find.text('Supported'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('feature_retention')),
        matching: find.text('Not set up'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('feature_threadNotifications')),
        matching: find.text('Supported'),
      ),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets('the card shows domain, software and upload limit', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.text('fakeServer.notExisting'), findsOneWidget);
    expect(find.text('Synapse 1.99.0 · upload limit 100 MB'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('an unreadable server shows Unknown and Offline', (tester) async {
    api.onRequest = (request) async {
      if (request.method == 'GET' &&
          (request.url.path.endsWith('/versions') ||
              request.url.path.endsWith('/capabilities') ||
              request.url.path.endsWith('/auth_metadata') ||
              request.url.path.endsWith('/matrix/client') ||
              request.url.path.contains('rtc/transports'))) {
        throw Exception('offline');
      }
    };
    await openPage(tester);
    expect(find.text('Unknown'), findsWidgets);
    expect(find.text('Offline'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a federation host outside the server is not asked', (
    tester,
  ) async {
    api.getOverrides['/matrix/server'] = {'m.server': 'evil.example.net:8448'};
    await openPage(tester);
    expect(api.log.where((r) => r.url.host == 'evil.example.net'), isEmpty);
    expect(api.requests('/federation/v1/version'), isEmpty);
    expect(find.textContaining('Synapse'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('every request goes to the homeserver or its subdomains', (
    tester,
  ) async {
    await openPage(tester);
    for (final request in api.log) {
      final host = request.url.host.toLowerCase();
      expect(
        host == 'fakeserver.notexisting' ||
            host.endsWith('.fakeserver.notexisting'),
        isTrue,
        reason: '${request.method} ${request.url}',
      );
    }
    await harness.finish(tester);
  });

  testWidgets('an oversized version answer is not read', (tester) async {
    api.getOverrides['/federation/v1/version'] = {
      'server': {'name': 'Synapse', 'version': '1.99.0'},
      'padding': 'x' * 70000,
    };
    await openPage(tester);
    expect(find.textContaining('Synapse'), findsNothing);
    expect(find.text('upload limit 100 MB'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('an oversized well-known answer is ignored', (tester) async {
    api.getOverrides['/matrix/server'] = {
      'm.server': 'federation.fakeserver.notexisting:8448',
      'padding': 'x' * 70000,
    };
    await openPage(tester);
    expect(
      api.log.where((r) => r.url.host == 'federation.fakeserver.notexisting'),
      isEmpty,
    );
    expect(
      api.requests('/federation/v1/version').single.url.host,
      'fakeserver.notexisting',
    );
    await harness.finish(tester);
  });

  testWidgets('Check again asks the server again', (tester) async {
    await openPage(tester);
    final before = api.requests('/versions').length;
    await tester.tap(find.byKey(const ValueKey('homeserver_check_again')));
    await harness.settle(tester, rounds: 6);
    expect(api.requests('/versions').length, greaterThan(before));
    await harness.finish(tester);
  });

  testWidgets('Share with your admin sends the report and no identity', (
    tester,
  ) async {
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('share_with_admin')));
    await harness.settle(tester, rounds: 4);
    expect(shared, hasLength(1));
    final text = shared.single['text']! as String;
    expect(text, contains('fakeServer.notExisting'));
    expect(text, contains('Sliding sync: Supported'));
    expect(text, contains('Disappearing messages: Not set up'));
    expect(text, isNot(contains('@test:')));
    expect(text, isNot(contains('ABCD1234')));
    expect(text, isNot(contains('1234')));
    await harness.finish(tester);
  });

  testWidgets('More server details opens the old details page', (tester) async {
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('homeserver_details')));
    await harness.settle(tester, rounds: 4);
    expect(find.byType(HomeserverDetails), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('320x480 has no overflow', (tester) async {
    await openPage(tester, width: 320, height: 480);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('homeserver_details')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });
}
