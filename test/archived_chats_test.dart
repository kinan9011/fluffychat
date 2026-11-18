// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat_list/key_backup_banner.dart';
import 'package:fluffychat/pages/global_search/global_search.dart';
import 'package:fluffychat/pages/global_search/global_search_view.dart';
import 'package:fluffychat/utils/crypto_identity.dart' as crypto_identity;
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:fluffychat/widgets/layouts/chats_badge.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/test_client.dart';

const _user = '%40test%3AfakeServer.notExisting';
const _archived = {'im.fluffychat.archived': null};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late FakeMatrixApi api;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    client = await prepareTestClient();
    client.backgroundSync = false;
    api = FakeMatrixApi.currentApi!;
    FakeMatrixApi.client = client;
    for (final id in ['ar1', 'ar2', 'ar3', 'ar4', 'ar5', 'ar6', 'arn']) {
      api.api['PUT']!['/client/v3/user/$_user/rooms/!$id%3Ax/tags/im.fluffychat.archived'] =
          (_) => {};
    }
  });

  setUp(() async {
    FakeMatrixApi.currentApi = api;
    await AppSettings.chatFilter.setItem('allChats');
  });

  tearDown(() {
    KeyBackupBanner.resetForTest();
    AppRoutes.isLoggedIn = AppRoutes.defaultIsLoggedIn;
    client.rooms.removeWhere((room) => room.id.startsWith('!ar'));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Room chat(
    String id,
    String name, {
    int unread = 0,
    Map<String, double?> tags = const {},
    int minutesAgo = 0,
  }) {
    final room = testChat(
      client,
      id,
      name: name,
      unread: unread,
      lastBody: 'hello',
      lastTime: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      tags: tags,
    );
    client.rooms.add(room);
    return room;
  }

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.state<MatrixState>(find.byType(Matrix)).setActiveClient(client);
    FluffyChatApp.router.go('/rooms');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  }

  Finder item(String id) => find.byKey(ValueKey('chat_list_item_$id'));

  final archivedRow = find.byKey(const ValueKey('archived_chats_row'));

  testWidgets('an archived chat leaves the list and shows in the row', (
    tester,
  ) async {
    chat('!ar1:x', 'Anna', tags: _archived);
    chat('!arn:x', 'Ben');
    await pumpList(tester);
    expect(item('!arn:x'), findsOneWidget);
    expect(item('!ar1:x'), findsNothing);
    expect(archivedRow, findsOneWidget);
    expect(find.text('Archived chats'), findsOneWidget);
    expect(
      find.descendant(of: archivedRow, matching: find.text('Anna')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(archivedRow).dy,
      lessThan(tester.getTopLeft(item('!arn:x')).dy),
      reason: 'the row is the first item',
    );
    await finish(tester);
  });

  testWidgets('the row names three chats and counts the rest', (tester) async {
    for (var i = 1; i <= 5; i++) {
      chat('!ar$i:x', 'Chat${'ABCDE'[i - 1]}', tags: _archived, minutesAgo: i);
    }
    await pumpList(tester);
    expect(
      find.descendant(
        of: archivedRow,
        matching: find.text('ChatA, ChatB, ChatC, 2 more'),
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('no archived chat, no row', (tester) async {
    chat('!arn:x', 'Ben');
    await pumpList(tester);
    expect(archivedRow, findsNothing);
    await finish(tester);
  });

  testWidgets('tapping the row lists only archived chats, back returns', (
    tester,
  ) async {
    chat('!ar1:x', 'Anna', tags: _archived);
    chat('!arn:x', 'Ben');
    await pumpList(tester);
    await tester.tap(archivedRow);
    await settle(tester);
    expect(item('!ar1:x'), findsOneWidget);
    expect(item('!arn:x'), findsNothing);
    expect(archivedRow, findsNothing);
    expect(find.text('Unread'), findsNothing, reason: 'tab bar is hidden');
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(item('!arn:x'), findsOneWidget);
    expect(item('!ar1:x'), findsNothing);
    expect(archivedRow, findsOneWidget);
    await finish(tester);
  });

  testWidgets('the system back leaves the archived view', (tester) async {
    chat('!ar1:x', 'Anna', tags: _archived);
    chat('!arn:x', 'Ben');
    await pumpList(tester);
    await tester.tap(archivedRow);
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(item('!arn:x'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('archived chats are not in the badge or the tab counts', (
    tester,
  ) async {
    chat('!ar1:x', 'Anna', unread: 3, tags: _archived);
    chat('!arn:x', 'Ben', unread: 1);
    final others = client.rooms
        .where(
          (room) =>
              !room.id.startsWith('!ar') &&
              !room.isSpace &&
              room.isUnreadOrInvited,
        )
        .length;
    await pumpList(tester);
    final badge = find.descendant(
      of: find.byType(AppBottomBar),
      matching: find.byType(ChatsBadge),
    );
    expect(
      find.descendant(of: badge.first, matching: find.text('${others + 1}')),
      findsOneWidget,
      reason: 'only Ben counts, not the archived Anna with 3',
    );
    expect(
      find.descendant(of: badge.first, matching: find.text('${others + 4}')),
      findsNothing,
    );
    await tester.tap(find.text('Unread'));
    await settle(tester);
    expect(item('!ar1:x'), findsNothing);
    expect(item('!arn:x'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the row only shows under All chats', (tester) async {
    chat('!ar1:x', 'Anna', unread: 2, tags: _archived);
    chat('!arn:x', 'Ben', unread: 1);
    await pumpList(tester);
    expect(archivedRow, findsOneWidget);
    await tester.tap(find.text('Unread'));
    await settle(tester);
    expect(archivedRow, findsNothing);
    await finish(tester);
  });

  testWidgets(
    'the key backup banner is on the list, not in search or archive',
    (tester) async {
      KeyBackupBanner.resetForTest();
      crypto_identity.loadCryptoIdentityConnected = (_) async => false;
      addTearDown(
        () => crypto_identity.loadCryptoIdentityConnected = noCryptoIdentity,
      );
      chat('!ar1:x', 'Anna', tags: _archived);
      chat('!arn:x', 'Ben');
      await pumpList(tester);
      expect(find.text('Back up your encryption keys'), findsOneWidget);
      await tester.tap(find.byTooltip('Search'));
      await settle(tester);
      expect(find.byType(GlobalSearch), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlobalSearch),
          matching: find.text('Back up your encryption keys'),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(GlobalSearchView.cancelKey));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GlobalSearch), findsNothing);
      expect(find.text('Back up your encryption keys'), findsOneWidget);
      await tester.tap(archivedRow);
      await settle(tester);
      expect(find.text('Back up your encryption keys'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('the context menu archives a chat', (tester) async {
    chat('!arn:x', 'Ben');
    FakeMatrixApi.calledEndpoints.clear();
    await pumpList(tester);
    await tester.tap(item('!arn:x'), buttons: kSecondaryButton);
    await settle(tester);
    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(
      FakeMatrixApi.calledEndpoints.keys.where(
        (path) => path.contains('/tags/'),
      ),
      ['/client/v3/user/$_user/rooms/!arn%3Ax/tags/im.fluffychat.archived'],
    );
    await finish(tester);
  });

  testWidgets('unarchiving the last chat leaves the archived view', (
    tester,
  ) async {
    final anna = chat('!ar1:x', 'Anna', tags: _archived);
    chat('!arn:x', 'Ben');
    await pumpList(tester);
    await tester.tap(archivedRow);
    await settle(tester);
    anna.roomAccountData.remove('m.tag');
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'unarchive',
          accountData: [BasicEvent(type: 'x.unarchive', content: {})],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(item('!ar1:x'), findsOneWidget);
    expect(item('!arn:x'), findsOneWidget);
    expect(archivedRow, findsNothing);
    await finish(tester);
  });
}
