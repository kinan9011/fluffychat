// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/chat_list/swipe_actions.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/test_client.dart';

const _user = '%40test%3AfakeServer.notExisting';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Client second;
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
    second = await prepareTestClient(clientName: 'Second swipe client');
    second.backgroundSync = false;
    FakeMatrixApi.client = second;
    for (final id in ['swa', 'swb', 'swc', 'swi', 'swl']) {
      for (final tag in ['im.fluffychat.archived', 'm.favourite']) {
        api.api['PUT']!['/client/v3/user/$_user/rooms/!$id%3Ax/tags/$tag'] =
            (_) => {};
        api.api['DELETE']!['/client/v3/user/$_user/rooms/!$id%3Ax/tags/$tag'] =
            (_) => {};
      }
      api.api['POST']!['/client/v3/rooms/!$id%3Ax/read_markers'] = (_) => {};
    }
  });

  setUp(() {
    FakeMatrixApi.currentApi = api;
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() {
    AppRoutes.isLoggedIn = AppRoutes.defaultIsLoggedIn;
    client.rooms.removeWhere((room) => room.id.startsWith('!sw'));
    second.rooms.removeWhere((room) => room.id.startsWith('!sw'));
  });

  Iterable<String> writes() => FakeMatrixApi.calledEndpoints.keys.where(
    (path) =>
        path.contains('/tags/') ||
        path.contains('/read_markers') ||
        path.contains('/account_data/'),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Room chat(
    String id, {
    int unread = 0,
    Membership membership = Membership.join,
    DateTime? time,
    Map<String, double?> tags = const {},
  }) {
    final room = testChat(
      client,
      id,
      name: id.substring(1, 4),
      unread: unread,
      membership: membership,
      lastBody: 'hello',
      lastTime: time ?? DateTime.now(),
      tags: tags,
    );
    client.rooms.add(room);
    return room;
  }

  group('runSwipeAction resolves the room when it runs', () {
    test('a left room causes no request at all', () async {
      final room = chat('!swl:x');
      room.membership = Membership.leave;
      for (final action in SwipeAction.values) {
        await runSwipeAction(client, '!swl:x', action, publicReceipts: true);
      }
      expect(writes(), isEmpty);
    });

    test('an invite causes no request at all', () async {
      chat('!swi:x', membership: Membership.invite);
      for (final action in SwipeAction.values) {
        await runSwipeAction(client, '!swi:x', action, publicReceipts: true);
      }
      expect(writes(), isEmpty);
    });

    test('an unknown room id causes no request at all', () async {
      for (final action in SwipeAction.values) {
        await runSwipeAction(client, '!gone:x', action, publicReceipts: true);
      }
      expect(writes(), isEmpty);
    });

    test('archive toggles the custom tag, never low priority', () async {
      chat('!swa:x');
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.archive,
        publicReceipts: true,
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (path) => path.contains('/tags/'),
        ),
        ['/client/v3/user/$_user/rooms/!swa%3Ax/tags/im.fluffychat.archived'],
      );
    });

    test('unarchive removes the tag', () async {
      chat('!swa:x', tags: {'im.fluffychat.archived': null});
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.archive,
        publicReceipts: true,
      );
      expect(
        FakeMatrixApi.calledEndpoints,
        contains(
          '/client/v3/user/$_user/rooms/!swa%3Ax/tags/im.fluffychat.archived',
        ),
      );
      expect(
        FakeMatrixApi
            .calledEndpoints['/client/v3/user/$_user/rooms/!swa%3Ax/tags/im.fluffychat.archived'],
        hasLength(1),
      );
    });

    test('pin puts a new pin on top of the existing ones', () async {
      chat('!swa:x');
      chat('!swb:x', tags: {'m.favourite': 0.4});
      chat('!swc:x', tags: {'m.favourite': 0.2});
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.pin,
        publicReceipts: true,
      );
      final body =
          jsonDecode(
                FakeMatrixApi
                        .calledEndpoints['/client/v3/user/$_user/rooms/!swa%3Ax/tags/m.favourite']!
                        .single
                    as String,
              )
              as Map;
      expect(body['order'], closeTo(0.1, 1e-9));
    });

    test('pin ignores hostile orders of other chats', () async {
      chat('!swa:x');
      chat('!swb:x', tags: {'m.favourite': double.infinity});
      chat('!swc:x', tags: {'m.favourite': -5});
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.pin,
        publicReceipts: true,
      );
      final body =
          jsonDecode(
                FakeMatrixApi
                        .calledEndpoints['/client/v3/user/$_user/rooms/!swa%3Ax/tags/m.favourite']!
                        .single
                    as String,
              )
              as Map;
      expect(body['order'], 0.5);
    });

    test('unpin removes the favourite tag', () async {
      chat('!swa:x', tags: {'m.favourite': 0.5});
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.pin,
        publicReceipts: true,
      );
      expect(
        FakeMatrixApi.calledEndpoints,
        contains('/client/v3/user/$_user/rooms/!swa%3Ax/tags/m.favourite'),
      );
    });

    test('mark read without public receipts sends no m.read', () async {
      chat('!swa:x', unread: 2);
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.toggleRead,
        publicReceipts: false,
      );
      final body =
          jsonDecode(
                FakeMatrixApi
                        .calledEndpoints['/client/v3/rooms/!swa%3Ax/read_markers']!
                        .single
                    as String,
              )
              as Map;
      expect(body.keys, containsAll(['m.fully_read', 'm.read.private']));
      expect(body.containsKey('m.read'), isFalse);
    });

    test('mark read never sends a marker for a local echo', () async {
      final room = chat('!swa:x', unread: 2);
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'pending'},
        room: room,
        eventId: 'transaction-id',
        senderId: client.userID!,
        originServerTs: DateTime.now(),
        status: EventStatus.sending,
      );
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.toggleRead,
        publicReceipts: true,
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (path) => path.contains('/read_markers'),
        ),
        isEmpty,
      );
    });

    test('mark read with public receipts sends m.read (control)', () async {
      chat('!swa:x', unread: 2);
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.toggleRead,
        publicReceipts: true,
      );
      final body =
          jsonDecode(
                FakeMatrixApi
                        .calledEndpoints['/client/v3/rooms/!swa%3Ax/read_markers']!
                        .single
                    as String,
              )
              as Map;
      expect(body.containsKey('m.read'), isTrue);
    });

    test('toggling a read chat marks it unread, nothing else', () async {
      chat('!swa:x');
      await runSwipeAction(
        client,
        '!swa:x',
        SwipeAction.toggleRead,
        publicReceipts: true,
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (path) => path.contains('/read_markers'),
        ),
        isEmpty,
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (path) => path.contains('marked_unread'),
        ),
        isNotEmpty,
      );
    });
  });

  testWidgets('an open tray still acts on its own room after a reorder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    chat('!swa:x', time: now);
    final beta = chat('!swb:x', time: now.subtract(const Duration(hours: 1)));
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

    final rowA = find.byKey(const ValueKey('chat_list_item_!swa:x'));
    final rowB = find.byKey(const ValueKey('chat_list_item_!swb:x'));
    expect(
      tester.getTopLeft(rowA).dy,
      lessThan(tester.getTopLeft(rowB).dy),
      reason: 'A starts above B',
    );
    await tester.drag(rowA, const Offset(-250, 0));
    await settle(tester);
    expect(find.text('Archive'), findsOneWidget);

    beta.lastEvent = Event(
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': 'newer'},
      room: beta,
      eventId: '\$newer',
      senderId: '@anna:example.org',
      originServerTs: now.add(const Duration(hours: 1)),
    );
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'reorder',
          accountData: [BasicEvent(type: 'x.reorder', content: {})],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(
      tester.getTopLeft(rowB).dy,
      lessThan(tester.getTopLeft(rowA).dy),
      reason: 'B is above A after the sync',
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('swipe_!swa:x')),
        matching: find.byKey(const ValueKey('swipe_archive')),
      ),
    );
    await settle(tester);
    final tags = FakeMatrixApi.calledEndpoints.keys.where(
      (path) => path.contains('/tags/'),
    );
    expect(tags, [
      '/client/v3/user/$_user/rooms/!swa%3Ax/tags/im.fluffychat.archived',
    ]);

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  });

  testWidgets('the leading swipe honours the public receipts setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await AppSettings.sendPublicReadReceipts.setItem(false);
    addTearDown(() => AppSettings.sendPublicReadReceipts.setItem(true));
    chat('!swa:x', unread: 2);
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
    await tester.drag(
      find.byKey(const ValueKey('chat_list_item_!swa:x')),
      const Offset(150, 0),
    );
    await settle(tester);
    final body =
        jsonDecode(
              FakeMatrixApi
                      .calledEndpoints['/client/v3/rooms/!swa%3Ax/read_markers']!
                      .single
                  as String,
            )
            as Map;
    expect(body.containsKey('m.read'), isFalse);
    expect(body.containsKey('m.read.private'), isTrue);

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  });

  testWidgets('an open tray closes when the active account changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final shared = chat('!swa:x');
    second.rooms.add(
      testChat(
        second,
        shared.id,
        name: 'swa',
        lastBody: 'hello',
        lastTime: DateTime.now(),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [client, second],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final matrix = tester.state<MatrixState>(find.byType(Matrix));
    matrix.setActiveClient(client);
    FluffyChatApp.router.go('/rooms');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.drag(
      find.byKey(const ValueKey('chat_list_item_!swa:x')),
      const Offset(-250, 0),
    );
    await settle(tester);
    expect(find.text('Archive'), findsOneWidget);
    matrix.setActiveClient(second);
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('chat_list_item_!swa:x')), findsOneWidget);
    expect(find.text('Archive'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  });
}
