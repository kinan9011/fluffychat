// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/calls/calls_page.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/profile/profile_page.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:fluffychat/widgets/layouts/app_nav_rail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

const _tabRoots = ['/rooms', '/calls', '/settings', '/profile'];

const _guardedSubRoutes = [
  '/rooms/archive',
  '/rooms/newprivatechat',
  '/rooms/newgroup',
  '/rooms/newspace',
  '/rooms/!abc:example.org',
  '/rooms/!abc:example.org/details',
  '/settings/security',
  '/settings/style',
  '/settings/devices',
  '/settings/addaccount',
  '/settings/homeserver',
  '/backup',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late SharedPreferences prefs;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
  });

  tearDown(() {
    AppRoutes.isLoggedIn = AppRoutes.defaultIsLoggedIn;
  });

  void routeTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        // lets the capability request timeouts of pages that were opened expire
        await tester.pump(const Duration(seconds: 35));
      });

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<String> goTo(WidgetTester tester, String location) async {
    FluffyChatApp.router.go(location);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    return FluffyChatApp.router.routeInformationProvider.value.uri.toString();
  }

  group('logged out', () {
    setUp(() => AppRoutes.isLoggedIn = (_) => false);

    for (final path in [..._tabRoots, ..._guardedSubRoutes]) {
      routeTest('$path is sent to /home', (tester) async {
        await pumpApp(tester);
        expect(await goTo(tester, path), '/home');
      });
    }

    routeTest('deep links do not reach tabs either', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, 'matrix:roomid/abc:example.org'), '/home');
      expect(await goTo(tester, '/rooms/settings/security'), '/home');
    });

    routeTest('/ goes to /home', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, '/'), '/home');
    });
  });

  group('logged in', () {
    routeTest('each tab shows its page', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, '/rooms'), '/rooms');
      expect(find.byType(ChatList), findsOneWidget);
      expect(await goTo(tester, '/calls'), '/calls');
      expect(find.byType(CallsPage), findsOneWidget);
      expect(await goTo(tester, '/settings'), '/settings');
      expect(find.byType(Settings), findsOneWidget);
      expect(await goTo(tester, '/profile'), '/profile');
      expect(find.byType(ProfilePage), findsOneWidget);
    });

    routeTest('/ and /home go to the chats tab', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, '/'), '/rooms');
      expect(await goTo(tester, '/home'), '/rooms');
    });

    routeTest('calls tab redirects to chats when calls are off', (
      tester,
    ) async {
      await pumpApp(tester);
      await AppSettings.callsEnabled.setItem(false);
      expect(await goTo(tester, '/calls'), '/rooms');
      await AppSettings.callsEnabled.setItem(true);
      expect(await goTo(tester, '/calls'), '/calls');
    });

    routeTest('desktop width: rail, list column and pane for every tab', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(1400, 800));
      expect(await goTo(tester, '/rooms'), '/rooms');
      expect(find.byType(AppNavRail), findsOneWidget);
      expect(find.byType(AppBottomBar), findsNothing);
      expect(find.byType(ChatList), findsOneWidget);
      expect(await goTo(tester, '/settings'), '/settings');
      expect(find.byType(Settings), findsOneWidget);
      expect(await goTo(tester, '/rooms/settings/style'), '/settings/style');
      expect(find.byType(Settings), findsOneWidget);
      expect(await goTo(tester, '/calls'), '/calls');
      expect(find.byType(CallsPage), findsOneWidget);
      expect(await goTo(tester, '/profile'), '/profile');
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    routeTest('the bottom bar shows on tab roots only', (tester) async {
      await pumpApp(tester);
      await goTo(tester, '/rooms');
      expect(find.byType(AppBottomBar).hitTestable(), findsOneWidget);
      await goTo(tester, '/settings/style');
      expect(find.byType(AppBottomBar).hitTestable(), findsNothing);
    });

    routeTest('tapping the bar switches tabs and keeps the other stack', (
      tester,
    ) async {
      await pumpApp(tester);
      await goTo(tester, '/settings/style');
      await goTo(tester, '/rooms');
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        FluffyChatApp.router.routeInformationProvider.value.uri.path,
        '/settings/style',
      );
      await goTo(tester, '/settings');
      await tester.tap(find.text('Profile'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        FluffyChatApp.router.routeInformationProvider.value.uri.path,
        '/profile',
      );
    });
  });

  group('links keep working', () {
    routeTest('matrix: and invite links', (tester) async {
      await pumpApp(tester);
      expect(
        await goTo(tester, 'matrix:roomid/abc:example.org'),
        '/rooms/!abc:example.org',
      );
      expect(
        await goTo(tester, 'matrix:r/room:example.org'),
        '/rooms/newprivatechat#%23room:example.org',
      );
      expect(
        await goTo(tester, 'matrix:u/alice:example.org'),
        '/rooms/newprivatechat#@alice:example.org',
      );
    });

    routeTest('malformed matrix: links cannot inject a path or query', (
      tester,
    ) async {
      await pumpApp(tester);
      for (final link in [
        'matrix:roomid/x%2F..%2F..%2Fsettings%2Fsecurity',
        'matrix:roomid/abc:example.org%3Faction%3Dcall',
        'matrix:u/alice:example.org%23x',
        'matrix:r/noserver',
        'matrix:roomid/${'a' * 300}',
      ]) {
        final result = await goTo(tester, link);
        expect(result, '/rooms', reason: link);
        expect(result, isNot(contains('action=call')), reason: link);
      }
    });

    routeTest('content sharing is ignored', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, 'content://media/external/1'), '/rooms');
    });

    routeTest('old settings links land on the settings tab', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, '/rooms/settings'), '/settings');
      expect(
        await goTo(tester, '/rooms/settings/security?client=a#frag'),
        '/settings/security?client=a#frag',
      );
    });

    routeTest('a room called settingsx is still a room', (tester) async {
      await pumpApp(tester);
      expect(await goTo(tester, '/rooms/settingsx'), '/rooms/settingsx');
    });

    routeTest('the rewrite never produces another host', (tester) async {
      await pumpApp(tester);
      for (final input in [
        '/rooms/settings//evil.example',
        '/rooms/settings/@evil.example',
      ]) {
        final result = Uri.parse(await goTo(tester, input));
        expect(result.host, isEmpty, reason: input);
        expect(result.scheme, isEmpty, reason: input);
        expect(result.path, startsWith('/'), reason: input);
        expect(result.path, isNot(startsWith('//')), reason: input);
      }
    });
  });
}
