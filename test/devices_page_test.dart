// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show MatrixSdkDatabase;
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/device_settings/device_settings.dart';
import 'package:odango/pages/device_settings/link_device_card.dart';
import 'package:odango/widgets/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  const own = 'ABCD1234';

  Map<String, Object?> device(String id, String name, int ago) => {
    'device_id': id,
    'display_name': name,
    'last_seen_ts': DateTime.now()
        .subtract(Duration(minutes: ago))
        .millisecondsSinceEpoch,
  };

  void serveDevices(List<Map<String, Object?>> others) {
    api.getOverrides['/devices'] = {
      'devices': [device(own, 'This test device', 0), ...others],
    };
  }

  final launched = <String>[];

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.getOverrides.clear();
    api.uiaPaths.clear();
    api.notFound.clear();
    await (harness.client.database as MatrixSdkDatabase)
        .clearCustomCacheObjects();
    api.onRequest = null;
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
            }
            return true;
          },
        );
    serveDevices([
      device('OTHER1', 'Firefox on Windows', 30),
      device('OTHER2', 'Galaxy Tab S9', 90),
    ]);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
    await harness.tearDown();
  });

  List<RecordedRequest> deletes() =>
      api.requests('delete_devices', method: 'POST');

  Future<void> openPage(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
  }) async {
    await harness.open(
      tester,
      path: '/settings/devices',
      width: width,
      height: height,
    );
    await harness.settle(tester, rounds: 8);
  }

  void cachePassword(WidgetTester tester) {
    tester.state<MatrixState>(find.byType(Matrix)).cachedPassword = 'secret';
  }

  Future<void> done(WidgetTester tester) async {
    await harness.finish(tester);
    await tester.pump(const Duration(minutes: 11));
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ok_cancel_alert_dialog_ok_button')));
    await harness.settle(tester, rounds: 8);
  }

  testWidgets('this device and the other sessions are listed', (tester) async {
    await openPage(tester);
    expect(find.byType(DevicesSettings), findsOneWidget);
    expect(find.text('THIS DEVICE'), findsOneWidget);
    expect(find.text('OTHER SESSIONS'), findsOneWidget);
    expect(find.text('This test device'), findsOneWidget);
    expect(find.text('Firefox on Windows'), findsOneWidget);
    expect(find.text('Galaxy Tab S9'), findsOneWidget);
    expect(find.text('Sign out all other sessions'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('sign_out_all_others')));
    await harness.settle(tester, rounds: 4);
    await tester.tap(find.text('Cancel'));
    await harness.settle(tester, rounds: 4);
    expect(deletes(), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('signing out the others goes through UIA and spares this one', (
    tester,
  ) async {
    api.uiaPaths.add('delete_devices');
    await openPage(tester);
    cachePassword(tester);
    await tester.tap(find.byKey(const ValueKey('sign_out_all_others')));
    await harness.settle(tester, rounds: 4);
    expect(deletes(), isEmpty, reason: 'nothing before the confirmation');
    await confirm(tester);
    final requests = deletes();
    expect(requests, hasLength(2));
    final first = requests.first.json! as Map;
    expect(first.containsKey('auth'), isFalse);
    final second = requests.last.json! as Map;
    expect(second['devices'], ['OTHER1', 'OTHER2']);
    expect(second['devices'], isNot(contains(own)));
    final auth = second['auth'] as Map;
    expect(auth['type'], 'm.login.password');
    expect(auth['session'], 'uia-session');
    await done(tester);
  });

  testWidgets('the list is read again after the confirmation', (tester) async {
    api.uiaPaths.add('delete_devices');
    await openPage(tester);
    cachePassword(tester);
    await tester.tap(find.byKey(const ValueKey('sign_out_all_others')));
    await harness.settle(tester, rounds: 4);
    serveDevices([
      device('OTHER1', 'Firefox on Windows', 30),
      device('OTHER3', 'New laptop', 1),
    ]);
    await confirm(tester);
    final sent = (deletes().last.json! as Map)['devices'] as List;
    expect(sent, ['OTHER1', 'OTHER3']);
    expect(sent, isNot(contains('OTHER2')));
    expect(sent, isNot(contains(own)));
    await done(tester);
  });

  testWidgets('one session can be signed out from its row', (tester) async {
    api.uiaPaths.add('delete_devices');
    await openPage(tester);
    cachePassword(tester);
    await tester.tap(find.byKey(const ValueKey('device_OTHER1')));
    await harness.settle(tester, rounds: 4);
    await tester.tap(find.text('Sign out this session'));
    await harness.settle(tester, rounds: 4);
    await confirm(tester);
    expect((deletes().last.json! as Map)['devices'], ['OTHER1']);
    await done(tester);
  });

  testWidgets('with an account page the app opens it and deletes nothing', (
    tester,
  ) async {
    api.getOverrides['/matrix/client'] = {
      'm.homeserver': {'base_url': 'https://fakeserver.notexisting'},
      'org.matrix.msc2965.authentication': {
        'account': 'https://account.example.org/manage',
      },
    };
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('sign_out_all_others')));
    await harness.settle(tester, rounds: 4);
    await confirm(tester);
    expect(deletes(), isEmpty);
    expect(launched, ['https://account.example.org/manage']);
    await harness.finish(tester);
  });

  testWidgets('an account page with a dangerous scheme is not opened', (
    tester,
  ) async {
    api.getOverrides['/matrix/client'] = {
      'm.homeserver': {'base_url': 'https://fakeserver.notexisting'},
      'org.matrix.msc2965.authentication': {'account': 'javascript:alert(1)'},
    };
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('sign_out_all_others')));
    await harness.settle(tester, rounds: 4);
    await confirm(tester);
    expect(deletes(), isEmpty);
    expect(launched, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('renaming sends the typed name for that device', (tester) async {
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('device_OTHER2')));
    await harness.settle(tester, rounds: 4);
    await tester.tap(find.text('Change device name'));
    await harness.settle(tester, rounds: 4);
    await tester.enterText(find.byType(TextField).last, 'Tablet');
    await tester.tap(find.text('Ok'));
    await harness.settle(tester, rounds: 6);
    final puts = api.requests('/devices/OTHER2', method: 'PUT');
    expect(puts, hasLength(1));
    expect(puts.single.json, {'display_name': 'Tablet'});
    await harness.finish(tester);
  });

  testWidgets('a failed load shows a retry that loads the list', (
    tester,
  ) async {
    var fail = true;
    api.onRequest = (request) async {
      if (fail &&
          request.method == 'GET' &&
          request.url.path.endsWith('/devices')) {
        throw Exception('offline');
      }
    };
    await openPage(tester);
    expect(find.byKey(const ValueKey('devices_retry')), findsOneWidget);
    expect(find.text('Firefox on Windows'), findsNothing);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('devices_retry')));
    await harness.settle(tester, rounds: 6);
    expect(find.text('Firefox on Windows'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('hostile device names are cleaned', (tester) async {
    serveDevices([
      device('OTHER1', 'Evil\u202E\u0000 name', 5),
      device('OTHER2', 'x' * 400, 6),
    ]);
    await openPage(tester);
    expect(find.textContaining('\u202E'), findsNothing);
    expect(
      find.textContaining(
        'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      ),
      findsNothing,
    );
    await harness.finish(tester);
  });

  testWidgets('320x480 scrolls without overflow', (tester) async {
    await openPage(tester, width: 320, height: 480);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sign_out_all_others')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  group('Link a device card', () {
    Future<void> serve({required bool msc4108, required bool oidc}) async {
      api.getOverrides['/versions'] = {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc4108': msc4108},
      };
      if (oidc) {
        api.getOverrides['/auth_metadata'] = {
          'authorization_endpoint': 'https://auth.example.org/oauth2/auth',
          'code_challenge_methods_supported': ['S256'],
          'grant_types_supported': ['authorization_code', 'refresh_token'],
          'issuer': 'https://auth.example.org/',
          'registration_endpoint': 'https://auth.example.org/oauth2/register',
          'response_modes_supported': ['query', 'fragment'],
          'response_types_supported': ['code'],
          'revocation_endpoint': 'https://auth.example.org/oauth2/revoke',
          'token_endpoint': 'https://auth.example.org/oauth2/token',
          'account_management_uri': 'https://auth.example.org/account',
        };
        return;
      }
      api.notFound.add('/auth_metadata');
    }

    testWidgets('shown when the server supports it, opens the account page', (
      tester,
    ) async {
      await serve(msc4108: true, oidc: true);
      await openPage(tester);
      expect(find.byType(LinkDeviceCard), findsOneWidget);
      expect(find.text('Link a device'), findsOneWidget);
      expect(find.textContaining("can't scan one yet"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('link_device_open_account')));
      await harness.settle(tester, rounds: 3);
      expect(launched, ['https://auth.example.org/account']);
      await harness.finish(tester);
    });

    testWidgets('absent when MAS is not detected', (tester) async {
      await serve(msc4108: true, oidc: false);
      await openPage(tester);
      expect(find.byType(LinkDeviceCard), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('absent when the server does not advertise it', (tester) async {
      await serve(msc4108: false, oidc: true);
      await openPage(tester);
      expect(find.byType(LinkDeviceCard), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('absent when nothing could be read', (tester) async {
      api.onRequest = (request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/versions')) {
          throw Exception('offline');
        }
      };
      await openPage(tester);
      expect(find.byType(LinkDeviceCard), findsNothing);
      await harness.finish(tester);
    });
  });
}
