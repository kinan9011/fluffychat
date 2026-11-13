// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:fluffychat/widgets/layouts/app_nav_rail.dart';
import 'package:fluffychat/widgets/layouts/app_shell.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';

GoRouter _router(
  StreamController<Object?> accountChanges,
  StreamController<Object?> clientChanges, {
  VoidCallback? onFirstShown,
}) {
  GoRoute tab(String path, {List<RouteBase> routes = const []}) => GoRoute(
    path: path,
    builder: (_, state) => Text('PAGE ${state.uri.path}'),
    routes: routes,
  );
  return GoRouter(
    initialLocation: '/rooms',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(
          navigationShell: shell,
          location: state.uri.path,
          accountSwitched: accountChanges.stream,
          activeClientChanged: clientChanges.stream,
          onFirstShown: onFirstShown,
          profileAvatar: (size) =>
              SizedBox.square(key: ValueKey('avatar_$size'), dimension: size),
          leftColumn: (context, tab) => Text('LEFT ${tab.name}'),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              tab('/rooms', routes: [tab(':roomid')]),
            ],
          ),
          StatefulShellBranch(routes: [tab('/calls')]),
          StatefulShellBranch(
            routes: [
              tab('/settings', routes: [tab('style')]),
            ],
          ),
          StatefulShellBranch(routes: [tab('/profile')]),
        ],
      ),
    ],
  );
}

void main() {
  late StreamController<Object?> accountChanges;
  late StreamController<Object?> clientChanges;
  var shownCalls = 0;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    accountChanges = StreamController<Object?>.broadcast();
    clientChanges = StreamController<Object?>.broadcast();
    shownCalls = 0;
    router = _router(
      accountChanges,
      clientChanges,
      onFirstShown: () => shownCalls++,
    );
  });

  tearDown(() async {
    await AppSettings.callsEnabled.setItem(true);
    accountChanges.close();
    clientChanges.close();
    router.dispose();
  });

  Future<void> pumpShell(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder bar() => find.byType(AppBottomBar);
  Finder rail() => find.byType(AppNavRail);
  Finder strip() => find.byType(AppTabStrip);
  Finder left() => find.textContaining('LEFT');

  group('responsive layout (DESIGN 12)', () {
    for (final width in [320.0, 599.0]) {
      testWidgets('$width px: mobile shell', (tester) async {
        await pumpShell(tester, width);
        expect(bar(), findsOneWidget);
        expect(rail(), findsNothing);
        expect(strip(), findsNothing);
        expect(left(), findsNothing);
        expect(find.text('PAGE /rooms'), findsOneWidget);
      });
    }

    for (final width in [600.0, 899.0]) {
      testWidgets('$width px: list and conversation, tabs above the list', (
        tester,
      ) async {
        await pumpShell(tester, width);
        expect(bar(), findsNothing);
        expect(rail(), findsNothing);
        expect(strip(), findsOneWidget);
        expect(find.text('LEFT chats'), findsOneWidget);
        expect(find.text('PAGE /rooms'), findsOneWidget);
        final list = tester.getRect(
          find
              .ancestor(
                of: find.text('LEFT chats'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(list.width, 350);
      });
    }

    for (final width in [900.0, 1279.0, 1280.0, 1920.0]) {
      testWidgets('$width px: rail, list and conversation', (tester) async {
        await pumpShell(tester, width);
        expect(bar(), findsNothing);
        expect(strip(), findsNothing);
        expect(rail(), findsOneWidget);
        expect(tester.getSize(rail()).width, 76);
        expect(find.text('LEFT chats'), findsOneWidget);
        expect(find.text('PAGE /rooms'), findsOneWidget);
      });
    }

    testWidgets('rail: avatar first, then Chats, Calls, Settings', (
      tester,
    ) async {
      await pumpShell(tester, 1000);
      final tooltips = tester
          .widgetList<Tooltip>(
            find.descendant(of: rail(), matching: find.byType(Tooltip)),
          )
          .map((t) => t.message)
          .toList();
      expect(tooltips, ['Profile', 'Chats', 'Calls', 'Settings']);
      await AppSettings.callsEnabled.setItem(false);
      await pumpShell(tester, 1001);
      final withoutCalls = tester
          .widgetList<Tooltip>(
            find.descendant(of: rail(), matching: find.byType(Tooltip)),
          )
          .map((t) => t.message)
          .toList();
      expect(withoutCalls, ['Profile', 'Chats', 'Settings']);
    });

    testWidgets('resizing across every breakpoint keeps working', (
      tester,
    ) async {
      await pumpShell(tester, 400);
      router.go('/rooms/abc');
      await tester.pumpAndSettle();
      for (final width in [700.0, 1000.0, 1400.0, 1000.0, 700.0, 400.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width');
        expect(find.text('PAGE /rooms/abc'), findsOneWidget, reason: '$width');
      }
    });

    testWidgets('visited list columns stay alive across tab switches', (
      tester,
    ) async {
      await pumpShell(tester, 1000);
      expect(find.text('LEFT chats'), findsOneWidget);
      router.go('/settings');
      await tester.pumpAndSettle();
      expect(find.text('LEFT settings'), findsOneWidget);
      expect(find.text('LEFT chats', skipOffstage: false), findsOneWidget);
      expect(find.text('LEFT profile', skipOffstage: false), findsNothing);
    });
  });

  group('tabs', () {
    testWidgets('rail selects tabs and keeps their stacks', (tester) async {
      await pumpShell(tester, 1000);
      router.go('/settings/style');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chats'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /rooms'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /settings/style'), findsOneWidget);
    });

    testWidgets('the rail avatar opens Profile', (tester) async {
      await pumpShell(tester, 1000);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /profile'), findsOneWidget);
    });

    testWidgets('tapping the active tab again returns to its root', (
      tester,
    ) async {
      await pumpShell(tester, 1000);
      router.go('/rooms/abc');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chats'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /rooms'), findsOneWidget);
    });

    testWidgets('the tab strip works at 700 px', (tester) async {
      await pumpShell(tester, 700);
      await tester.tap(find.byTooltip('Calls'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /calls'), findsOneWidget);
      expect(find.text('LEFT calls'), findsOneWidget);
    });
  });

  group('account switch', () {
    testWidgets('every tab goes back to its root, the current one stays', (
      tester,
    ) async {
      await pumpShell(tester, 400);
      router.go('/settings/style');
      await tester.pumpAndSettle();
      router.go('/rooms/abc');
      await tester.pumpAndSettle();
      router.go('/profile');
      await tester.pumpAndSettle();
      accountChanges.add(Object());
      await tester.pumpAndSettle();
      expect(find.text('PAGE /profile'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /settings'), findsOneWidget);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE /rooms'), findsOneWidget);
    });

    testWidgets('a destination switch resets every other tab and keeps the '
        'current page', (tester) async {
      await pumpShell(tester, 400);
      router.go('/settings/style');
      await tester.pumpAndSettle();
      router.go('/rooms/abc');
      await tester.pumpAndSettle();
      clientChanges.add(Object());
      await tester.pumpAndSettle();
      expect(find.text('PAGE /rooms/abc'), findsOneWidget);
      tester
          .state<StatefulNavigationShellState>(
            find.byType(StatefulNavigationShell),
          )
          .goBranch(2);
      await tester.pumpAndSettle();
      expect(find.text('PAGE /settings'), findsOneWidget);
    });

    testWidgets('the hidden reset is excluded from semantics', (tester) async {
      await pumpShell(tester, 400);
      accountChanges.add(Object());
      await tester.pump();
      await tester.pump();
      expect(
        find.ancestor(
          of: find.byType(AppBottomBar),
          matching: find.byWidgetPredicate(
            (w) => w is ExcludeSemantics && w.excluding,
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  });

  group('first shown', () {
    testWidgets('is called once across resizes', (tester) async {
      await pumpShell(tester, 400);
      expect(shownCalls, 1);
      for (final width in [700.0, 1280.0, 400.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(shownCalls, 1, reason: '$width');
      }
    });
  });

  group('keyboard focus', () {
    bool barCanTakeFocus() =>
        FocusManager.instance.rootScope.traversalDescendants.any(
          (node) =>
              node.context?.findAncestorWidgetOfExactType<AppBottomBar>() !=
              null,
        );

    testWidgets('the bar takes focus on a tab root', (tester) async {
      await pumpShell(tester, 400);
      expect(barCanTakeFocus(), isTrue);
    });

    testWidgets('a hidden bar does not take focus', (tester) async {
      await pumpShell(tester, 400);
      router.go('/rooms/abc');
      await tester.pumpAndSettle();
      expect(barCanTakeFocus(), isFalse);
    });
  });

  group('golden', () {
    testWidgets('rail (light, dark, RTL)', (tester) async {
      await expectGoldenVariants(
        tester,
        'app_nav_rail',
        Row(
          children: [
            AppNavRail(
              tabs: AppTab.visible(callsEnabled: true),
              selected: AppTab.chats,
              onSelect: (_) {},
              accountCount: 2,
              profileAvatar: const CircleAvatar(
                radius: 21,
                backgroundColor: Colors.orange,
                child: Text('AL'),
              ),
            ),
          ],
        ),
        size: const Size(300, 400),
      );
    });

    testWidgets('tab strip (light, dark, RTL)', (tester) async {
      await expectGoldenVariants(
        tester,
        'app_tab_strip',
        AppTabStrip(
          tabs: AppTab.visible(callsEnabled: true),
          selected: AppTab.settings,
          onSelect: (_) {},
          profileAvatar: const CircleAvatar(
            backgroundColor: Colors.orange,
            child: Text('A', style: TextStyle(fontSize: 9)),
          ),
        ),
        size: const Size(350, 120),
      );
    });
  });
}
