// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/calls/calls_page.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/utils/app_start_hooks.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_quarantine_notice.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/layouts/app_nav_rail.dart';
import 'package:fluffychat/widgets/layouts/app_shell.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/own_avatar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/space_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client first;
  late Client second;
  late Client stranger;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    first = await prepareTestClient();
    first.backgroundSync = false;
    second = await prepareTestClient(clientName: 'Second');
    second.backgroundSync = false;
    stranger = await prepareTestClient(clientName: 'Stranger');
  });

  tearDown(() async {
    AppRoutes.isLoggedIn = AppRoutes.defaultIsLoggedIn;
    MatrixState.startupHooks = MatrixState.defaultStartupHooks;
    SettingsController.loadCryptoIdentityConnected =
        SettingsController.defaultLoadCryptoIdentityConnected;
    await AppSettings.callsEnabled.setItem(true);
  });

  StatefulNavigationShellState shell(WidgetTester tester) =>
      tester.state(find.byType(StatefulNavigationShell));

  /// Requests go through a real database isolate (real time) while their
  /// continuations run on the fake clock, so alternate between both.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void accountTest(
    String name,
    Future<MatrixState> Function(WidgetTester, MatrixState) body, {
    double width = 400,
    void Function()? beforePump,
    String startAt = '/rooms',
    List<Client> Function()? clients,
  }) => testWidgets(name, (tester) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    beforePump?.call();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: clients?.call() ?? [first, second],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    FluffyChatApp.router.go(startAt);
    await tester.pump(const Duration(milliseconds: 500));
    final matrix = tester.state<MatrixState>(find.byType(Matrix));
    matrix.setActiveClient(first);
    await body(tester, matrix);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  });

  String location() =>
      FluffyChatApp.router.routeInformationProvider.value.uri.toString();

  Future<void> goTo(WidgetTester tester, String target) async {
    FluffyChatApp.router.go(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('startup hooks', () {
    var runs = 0;
    var chatListsAtRun = -1;

    void countRuns() => MatrixState.startupHooks = (_) {
      runs++;
      chatListsAtRun = find.byType(ChatList).evaluate().length;
    };

    setUp(() {
      runs = 0;
      chatListsAtRun = -1;
    });

    accountTest('run once across breakpoint changes', (tester, matrix) async {
      await goTo(tester, '/rooms');
      await settle(tester);
      expect(runs, 1);
      expect(find.byType(ChatList), findsOneWidget);
      for (final width in [700.0, 400.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 800);
        await settle(tester);
        expect(runs, 1, reason: 'after resizing to $width');
      }
      matrix.runStartupHooksOnce();
      expect(runs, 1);
      return matrix;
    }, beforePump: countRuns);

    accountTest('run once even when the shell is rebuilt', (
      tester,
      matrix,
    ) async {
      await settle(tester);
      expect(runs, 1);
      FluffyChatApp.router.go('/logs');
      await settle(tester);
      FluffyChatApp.router.go('/rooms');
      await settle(tester);
      expect(runs, 1, reason: 'the shell was rebuilt, the flag must hold');
      return matrix;
    }, beforePump: countRuns);

    accountTest(
      'run when the app starts on another tab',
      (tester, matrix) async {
        await settle(tester);
        expect(runs, 1);
        expect(
          chatListsAtRun,
          0,
          reason: 'the trigger must not depend on a built ChatList',
        );
        return matrix;
      },
      beforePump: countRuns,
      startAt: '/settings',
    );
  });

  group('MatrixState.setActiveClient', () {
    accountTest('events only fire when the resolved client changes', (
      tester,
      matrix,
    ) async {
      final changed = <Client>[];
      final switched = <Client>[];
      final subscriptions = [
        matrix.onActiveClientChanged.listen(changed.add),
        matrix.onAccountSwitched.listen(switched.add),
      ];
      matrix.setActiveClient(first);
      await tester.pump();
      expect(changed, isEmpty, reason: 'already the active client');
      matrix.setActiveClient(second);
      await tester.pump();
      expect(changed, [second]);
      expect(switched, [second]);
      expect(matrix.client, second);
      matrix.setActiveClient(second);
      await tester.pump();
      expect(changed, [second], reason: 're-selecting is not a change');
      matrix.setActiveClient(first, resetTabs: false);
      await tester.pump();
      expect(changed, [second, first]);
      expect(switched, [second], reason: 'links and notifications keep tabs');
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      return matrix;
    });

    accountTest('an unknown client changes nothing and does not throw', (
      tester,
      matrix,
    ) async {
      final changed = <Client>[];
      final subscription = matrix.onActiveClientChanged.listen(changed.add);
      matrix.setActiveClient(stranger);
      matrix.setActiveClient(null);
      await tester.pump();
      expect(changed, isEmpty);
      expect(matrix.client, first);
      unawaited(subscription.cancel());
      return matrix;
    });

    accountTest('logging out the active account switches to the other one', (
      tester,
      matrix,
    ) async {
      matrix.setActiveClient(second);
      await tester.pump();
      final changed = <Client>[];
      final subscription = matrix.onActiveClientChanged.listen(changed.add);
      second.onLoginStateChanged.add(LoginState.loggedOut);
      await tester.pump();
      expect(matrix.widget.clients, [first]);
      expect(matrix.client, first);
      expect(changed, [first]);
      unawaited(subscription.cancel());
      return matrix;
    });

    for (final width in [400.0, 700.0, 1280.0]) {
      accountTest(
        'logging out the last account leaves the tabs intact at $width px',
        (tester, matrix) async {
          await goTo(tester, '/profile');
          await settle(tester);
          final original = FlutterError.onError;
          final errors = <Object>[];
          FlutterError.onError = (details) => errors.add(details.exception);
          // The "one account logged out" snackbar has no Scaffold to show in
          // beneath the column layout's own ScaffoldMessenger (pre-existing).
          if (width < 600) {
            second.onLoginStateChanged.add(LoginState.loggedOut);
          } else {
            matrix.widget.clients.remove(second);
          }
          first.onLoginStateChanged.add(LoginState.loggedOut);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          FlutterError.onError = original;
          expect(matrix.widget.clients, isEmpty);
          expect(matrix.activeClientOrNull, isNull);
          expect(errors.whereType<StateError>(), isEmpty, reason: '$errors');
          expect(location(), '/home');
          return matrix;
        },
        width: width,
      );
    }

    accountTest('removing another account keeps the active one', (
      tester,
      matrix,
    ) async {
      matrix.setActiveClient(second);
      await tester.pump();
      final changed = <Client>[];
      final subscription = matrix.onActiveClientChanged.listen(changed.add);
      first.onLoginStateChanged.add(LoginState.loggedOut);
      await tester.pump();
      expect(matrix.widget.clients, [second]);
      expect(matrix.client, second, reason: 'indexes shifted, client did not');
      expect(changed, isEmpty);
      unawaited(subscription.cancel());
      return matrix;
    });
  });

  group('a destination wins over an account switch', () {
    accountTest('a link into another account keeps its destination', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/rooms/newprivatechat?client=Second');
      await settle(tester);
      expect(matrix.client, second);
      expect(location(), '/rooms/newprivatechat?client=Second');
      return matrix;
    });

    accountTest('a deeper tab page of another account is kept as well', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/settings/style?client=Second');
      await settle(tester);
      expect(matrix.client, second);
      expect(location(), '/settings/style?client=Second');
      return matrix;
    });

    accountTest('a notification tap for another account opens its chat', (
      tester,
      matrix,
    ) async {
      final roomId = second.rooms.first.id;
      await goTo(tester, '/rooms/$roomId?client=Second');
      await settle(tester);
      expect(matrix.client, second);
      expect(location(), '/rooms/$roomId?client=Second');
      return matrix;
    });

    accountTest('joining a call switches the account without a tab reset', (
      tester,
      matrix,
    ) async {
      final roomId = second.rooms.first.id;
      matrix.setActiveClient(second, resetTabs: false);
      await goTo(tester, '/rooms/$roomId');
      await settle(tester);
      expect(matrix.client, second);
      expect(location(), '/rooms/$roomId');
      return matrix;
    });

    for (final width in [400.0, 1280.0]) {
      accountTest('a destination switch resets the other tabs at $width px', (
        tester,
        matrix,
      ) async {
        final roomId = second.rooms.first.id;
        await goTo(tester, '/settings/style');
        await goTo(tester, '/rooms/$roomId?client=Second');
        await settle(tester);
        expect(location(), '/rooms/$roomId?client=Second');
        shell(tester).goBranch(AppTab.settings.index);
        await settle(tester);
        expect(location(), '/settings');
        return matrix;
      }, width: width);
    }

    accountTest('a disabled calls tab does not swallow the destination', (
      tester,
      matrix,
    ) async {
      await AppSettings.callsEnabled.setItem(false);
      final roomId = second.rooms.first.id;
      await goTo(tester, '/settings/style');
      await goTo(tester, '/rooms/$roomId?client=Second');
      await settle(tester);
      expect(location(), '/rooms/$roomId?client=Second');
      return matrix;
    });

    accountTest('joining a call keeps its destination and resets other tabs', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/settings/style');
      await goTo(tester, '/rooms');
      matrix.joinCall(second, '!nothere:fakeServer.notExisting');
      await settle(tester);
      expect(matrix.client, second);
      expect(location(), '/rooms/!nothere:fakeServer.notExisting?action=call');
      shell(tester).goBranch(AppTab.settings.index);
      await settle(tester);
      expect(location(), '/settings');
      return matrix;
    });

    accountTest('an account switch does not hijack a navigation out of tabs', (
      tester,
      matrix,
    ) async {
      matrix.setActiveClient(second, resetTabs: false);
      FluffyChatApp.router.go('/logs');
      await settle(tester);
      expect(location(), '/logs');
      return matrix;
    });

    accountTest('changing the sending account in a chat keeps the chat', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/rooms/${first.rooms.first.id}');
      await settle(tester);
      tester
          .state<ChatController>(find.byType(ChatPageWithRoom))
          .setActiveClient(second);
      await settle(tester);
      expect(matrix.client, second);
      expect(location(), '/rooms/${first.rooms.first.id}');
      return matrix;
    });

    accountTest('a user switch sends every tab back to its root', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/settings/style');
      await goTo(tester, '/rooms');
      matrix.setActiveClient(second);
      await settle(tester);
      expect(location(), '/rooms');
      await goTo(tester, '/settings');
      expect(location(), '/settings');
      return matrix;
    });
  });

  group('per account state in kept alive tabs', () {
    accountTest('Settings reloads its profile for the new account', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/settings');
      await settle(tester);
      final controller = tester.state<SettingsController>(
        find.byType(Settings),
      );
      final before = controller.profileFuture;
      expect(before, isNotNull);
      matrix.setActiveClient(second, resetTabs: false);
      await settle(tester);
      expect(controller.profileFuture, isNotNull);
      expect(controller.profileFuture, isNot(same(before)));
      return matrix;
    });

    accountTest('a late chat backup state of the previous account is ignored', (
      tester,
      matrix,
    ) async {
      final pending = <Client, Completer<bool?>>{};
      SettingsController.loadCryptoIdentityConnected = (client) =>
          (pending[client] = Completer<bool?>()).future;
      await goTo(tester, '/settings');
      await tester.pump();
      expect(pending[first], isNotNull);
      matrix.setActiveClient(second);
      await tester.pump();
      expect(pending[second], isNotNull);
      pending[second]!.complete(false);
      await tester.pump();
      pending[first]!.complete(true);
      await settle(tester);
      final controller = tester.state<SettingsController>(
        find.byType(Settings),
      );
      expect(controller.cryptoIdentityConnected, false);
      return matrix;
    });

    accountTest('Calls loads the capabilities of the new account', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/calls');
      await settle(tester);
      expect(find.byType(CallsPage), findsOneWidget);
      expect(
        matrix.serverCapabilities.cached(first)[ServerFeature.groupCalls],
        isNot(FeatureSupport.unknown),
      );
      expect(
        matrix.serverCapabilities.cached(second),
        ServerCapabilities.unknown,
      );
      matrix.setActiveClient(second, resetTabs: false);
      await settle(tester);
      expect(
        matrix.serverCapabilities.cached(second)[ServerFeature.groupCalls],
        isNot(FeatureSupport.unknown),
      );
      return matrix;
    });
  });

  group('wiring of earlier fixes', () {
    ServerCapabilities cached(MatrixState matrix, Client client) =>
        matrix.serverCapabilities.cached(client);

    tearDown(
      () => first.rooms.removeWhere(
        (room) => room.id == '!space:example.org' || room.id == '!a:x',
      ),
    );

    accountTest(
      'a joined space row shows the space bubble',
      (tester, matrix) async {
        await goTo(tester, '/rooms');
        await settle(tester);
        expect(find.byType(SpaceUnreadBubble), findsOneWidget);
        return matrix;
      },
      beforePump: () => first.rooms.addAll([
        testSpace(first, ['!a:x']),
        testSpaceChild(first, '!a:x', unread: 1),
      ]),
    );

    accountTest('logging out forgets the cached server capabilities', (
      tester,
      matrix,
    ) async {
      await tester.runAsync(() => matrix.serverCapabilities.load(second));
      expect(cached(matrix, second), isNot(same(ServerCapabilities.unknown)));
      second.onLoginStateChanged.add(LoginState.loggedOut);
      await tester.pump();
      expect(cached(matrix, second), same(ServerCapabilities.unknown));
      return matrix;
    });

    accountTest('logging in loads the server capabilities of the new account', (
      tester,
      matrix,
    ) async {
      await AppSettings.callsEnabled.setItem(false);
      expect(cached(matrix, stranger), same(ServerCapabilities.unknown));
      matrix.addLoggedInClient(stranger);
      await settle(tester);
      expect(cached(matrix, stranger), isNot(same(ServerCapabilities.unknown)));
      expect(matrix.loggedInAccountCount.value, 3);
      expect(matrix.client, stranger);
      return matrix;
    });

    accountTest('a changed own profile reloads the avatar in the bar', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/rooms');
      await settle(tester);
      Future<Profile>? avatarFuture() => tester
          .widget<FutureBuilder<Profile>>(
            find
                .descendant(
                  of: find.byType(OwnAvatar),
                  matching: find.byType(FutureBuilder<Profile>),
                )
                .first,
          )
          .future;
      final before = avatarFuture();
      matrix.notifyOwnProfileChanged();
      await settle(tester);
      expect(avatarFuture(), isNot(same(before)));
      return matrix;
    });

    accountTest('the rail badge follows the number of logged in accounts', (
      tester,
      matrix,
    ) async {
      bool badgeVisible() => tester
          .widget<Badge>(
            find.descendant(
              of: find.byType(AppNavRail),
              matching: find.byType(Badge),
            ),
          )
          .isLabelVisible;
      await settle(tester);
      expect(matrix.loggedInAccountCount.value, 2);
      expect(badgeVisible(), isTrue);
      matrix.loggedInAccountCount.value = 1;
      await tester.pump();
      expect(badgeVisible(), isFalse);
      return matrix;
    }, width: 1000);
  });

  group('system back', () {
    Future<bool> back(WidgetTester tester) async {
      final handled = await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      return handled;
    }

    for (final root in ['/calls', '/settings', '/profile']) {
      accountTest('back from $root goes to the chats tab', (
        tester,
        matrix,
      ) async {
        await goTo(tester, root);
        await back(tester);
        expect(location(), '/rooms');
        return matrix;
      });
    }

    accountTest('back inside a tab goes up one page first', (
      tester,
      matrix,
    ) async {
      await goTo(tester, '/settings/style');
      await back(tester);
      expect(location(), '/settings');
      await back(tester);
      expect(location(), '/rooms');
      return matrix;
    });

    accountTest('back on the chats root is left to the system', (
      tester,
      matrix,
    ) async {
      final system = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            system.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await goTo(tester, '/rooms');
      await back(tester);
      expect(location(), '/rooms');
      expect(
        system.map((call) => call.method),
        contains('SystemNavigator.pop'),
      );
      return matrix;
    });
  });

  group('callkit rejoin', () {
    const roomId = '!nothere:fakeServer.notExisting';
    CallKitParams call({
      required String id,
      required bool accepted,
      String clientName = 'Second',
    }) => CallKitParams(
      id: id,
      isAccepted: accepted,
      extra: {'roomId': roomId, 'clientName': clientName},
    );

    accountTest('an accepted entry without another participant is ended', (
      tester,
      matrix,
    ) async {
      final ended = <String>[];
      final before = location();

      await rejoinAcceptedCall(
        [call(id: 'c1', accepted: true)],
        matrix,
        hasActiveCall: (_, _) async => false,
        endCall: (id) async => ended.add(id),
      );
      await settle(tester);

      expect(ended, ['c1']);
      expect(location(), before);
      expect(matrix.client, first);
      return matrix;
    });

    accountTest('an accepted entry with another participant is joined', (
      tester,
      matrix,
    ) async {
      final ended = <String>[];
      Client? checkedClient;

      await rejoinAcceptedCall(
        [call(id: 'c1', accepted: true)],
        matrix,
        hasActiveCall: (client, _) async {
          checkedClient = client;
          return true;
        },
        endCall: (id) async => ended.add(id),
      );
      await settle(tester);

      expect(ended, isEmpty);
      expect(checkedClient, second);
      expect(location(), '/rooms/$roomId?action=call');
      expect(matrix.client, second);
      return matrix;
    });

    accountTest('a ringing entry is never checked or joined', (
      tester,
      matrix,
    ) async {
      var checks = 0;
      final before = location();

      await rejoinAcceptedCall(
        [call(id: 'c1', accepted: false)],
        matrix,
        hasActiveCall: (_, _) async {
          checks++;
          return true;
        },
        endCall: (_) async => fail('nothing to end'),
      );
      await settle(tester);

      expect(checks, 0);
      expect(location(), before);
      expect(matrix.client, first);
      return matrix;
    });

    accountTest('an entry of an unknown account is ignored', (
      tester,
      matrix,
    ) async {
      await rejoinAcceptedCall(
        [call(id: 'c1', accepted: true, clientName: 'Nobody')],
        matrix,
        hasActiveCall: (_, _) async => fail('no target'),
        endCall: (_) async => fail('no target'),
      );
      expect(matrix.client, first);
      return matrix;
    });

    accountTest('an accept event joins a logged in account directly', (
      tester,
      matrix,
    ) async {
      await onCallKitEvent(
        matrix,
        CallEventActionCallAccept(call(id: 'c1', accepted: false)),
      );
      await settle(tester);

      expect(location(), '/rooms/$roomId?action=call');
      expect(matrix.client, second);
      return matrix;
    });

    accountTest('an accept event of an unknown account does nothing', (
      tester,
      matrix,
    ) async {
      final before = location();
      await onCallKitEvent(
        matrix,
        CallEventActionCallAccept(
          call(id: 'c1', accepted: false, clientName: 'Nobody'),
        ),
      );
      await settle(tester);

      expect(location(), before);
      expect(matrix.client, first);
      return matrix;
    });

    accountTest('an ended event clears the active call room', (
      tester,
      matrix,
    ) async {
      final params = call(id: 'c1', accepted: true);
      matrix.activeCallRoomId.value = roomId;

      await onCallKitEvent(matrix, CallEventActionCallEnded(params));

      expect(matrix.activeCallRoomId.value, isNull);
      return matrix;
    });
  });
  group('shell banners (A15)', () {
    void setFlags({bool unencrypted = false, bool quarantined = false}) {
      unencryptedClientsThisSession.clear();
      if (unencrypted) unencryptedClientsThisSession.add('a');
      AppSettings.store.setStringList(
        AppSettings.databaseQuarantinedClients.key,
        quarantined ? ['a'] : [],
      );
      AppSettings.store.setBool(
        AppSettings.databaseUnencryptedNoticeDismissed.key,
        false,
      );
    }

    tearDown(setFlags);

    Finder banners() => find.byType(MaterialBanner);

    for (final width in [400.0, 1280.0]) {
      accountTest(
        'an unencrypted database shows one banner at $width px',
        (tester, matrix) async {
          await settle(tester);
          expect(banners(), findsOneWidget);
          expect(find.text('Your local data is not encrypted'), findsOneWidget);
          return matrix;
        },
        width: width,
        beforePump: () => setFlags(unencrypted: true),
      );

      accountTest(
        'a quarantined database shows one banner at $width px',
        (tester, matrix) async {
          await settle(tester);
          expect(banners(), findsOneWidget);
          expect(find.textContaining('moved aside'), findsOneWidget);
          return matrix;
        },
        width: width,
        beforePump: () => setFlags(quarantined: true),
      );

      accountTest('no banner without a flag at $width px', (
        tester,
        matrix,
      ) async {
        await settle(tester);
        expect(banners(), findsNothing);
        return matrix;
      }, width: width);
    }

    accountTest('both notices show, and survive a tab change', (
      tester,
      matrix,
    ) async {
      await settle(tester);
      expect(banners(), findsNWidgets(2));
      await goTo(tester, '/settings');
      await settle(tester);
      expect(banners(), findsNWidgets(2));
      return matrix;
    }, beforePump: () => setFlags(unencrypted: true, quarantined: true));

    accountTest('closing a banner keeps the shell state', (
      tester,
      matrix,
    ) async {
      await settle(tester);
      final appShell = tester.state(find.byType(AppShell));
      final chatList = tester.state<ChatListController>(find.byType(ChatList));
      await tester.tap(find.text('Close').first);
      await settle(tester);
      expect(banners(), findsOneWidget);
      expect(tester.state(find.byType(AppShell)), same(appShell));
      expect(
        tester.state<ChatListController>(find.byType(ChatList)),
        same(chatList),
      );
      expect(hasDatabaseQuarantineNotice, isFalse);
      return matrix;
    }, beforePump: () => setFlags(unencrypted: true, quarantined: true));

    accountTest('the security action opens the security settings', (
      tester,
      matrix,
    ) async {
      await settle(tester);
      await tester.tap(find.text('Security'));
      await settle(tester);
      expect(location(), '/settings/security');
      expect(banners(), findsNothing);
      return matrix;
    }, beforePump: () => setFlags(unencrypted: true));

    accountTest('a dismissed unencrypted notice stays away', (
      tester,
      matrix,
    ) async {
      await settle(tester);
      await tester.tap(find.text('Close'));
      await settle(tester);
      expect(banners(), findsNothing);
      expect(AppSettings.databaseUnencryptedNoticeDismissed.value, isTrue);
      return matrix;
    }, beforePump: () => setFlags(unencrypted: true));
  });
}
