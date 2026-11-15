// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat_list/peek_sheet.dart';
import 'package:fluffychat/utils/chat_list/peek_menu.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

const _user = '%40test%3AfakeServer.notExisting';
const _roomId = '!peek:x';
const _roomPath = '!peek%3Ax';

final _forbidden = RegExp(
  r'/read_markers|/receipt/|/typing/|/presence/|/profile/'
  r'|/account_data/(m\.marked_unread|com\.famedly\.marked_unread|m\.fully_read)'
  r'|/sendToDevice/m\.room_key_request|/context/|/messages',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late FakeMatrixApi api;
  var syncs = 0;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
    client = await prepareTestClient();
    client.backgroundSync = false;
    api = FakeMatrixApi.currentApi!;
    FakeMatrixApi.client = client;
    for (final tag in ['im.fluffychat.archived', 'm.favourite']) {
      api.api['PUT']!['/client/v3/user/$_user/rooms/$_roomPath/tags/$tag'] =
          (_) => {};
      api.api['DELETE']!['/client/v3/user/$_user/rooms/$_roomPath/tags/$tag'] =
          (_) => {};
    }
    api.api['POST']!['/client/v3/rooms/$_roomPath/read_markers'] = (_) => {};
    api.api['POST']!['/client/v3/rooms/$_roomPath/leave'] = (_) => {};
  });

  setUp(() {
    FakeMatrixApi.currentApi = api;
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() {
    AppRoutes.isLoggedIn = AppRoutes.defaultIsLoggedIn;
    client.rooms.removeWhere((room) => room.id.startsWith('!peek'));
  });

  MatrixEvent message(String id, String body, {String? sender}) => MatrixEvent(
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': body},
    eventId: '\$$id',
    senderId: sender ?? '@anna:example.org',
    originServerTs: DateTime.now(),
  );

  Future<void> sync(
    WidgetTester tester,
    List<MatrixEvent> events, {
    bool first = false,
    String roomId = _roomId,
  }) => tester.runAsync(
    () => client.handleSync(
      SyncUpdate(
        nextBatch: 'peek${syncs++}',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                events: [
                  if (first)
                    MatrixEvent(
                      type: EventTypes.RoomName,
                      stateKey: '',
                      content: {'name': 'Anna'},
                      eventId: '\$name',
                      senderId: '@anna:example.org',
                      originServerTs: DateTime.now(),
                    ),
                  ...events,
                ],
              ),
              unreadNotifications: first
                  ? UnreadNotificationCounts(notificationCount: 2)
                  : null,
              accountData: first
                  ? [
                      BasicEvent(
                        type: 'm.marked_unread',
                        content: {'unread': true},
                      ),
                    ]
                  : null,
            ),
          },
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(WidgetTester tester, {double width = 400}) async {
    tester.view.physicalSize = Size(width, 800);
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
    await sync(tester, [
      message('1', 'first message'),
      message('2', 'second <b>message</b>'),
      message('3', 'mine', sender: client.userID),
    ], first: true);
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

  final row = find.byKey(const ValueKey('chat_list_item_$_roomId'));
  const notice = "Peeking: Anna won't see that you read this";

  Iterable<String> forbidden() =>
      FakeMatrixApi.calledEndpoints.keys.where(_forbidden.hasMatch);

  testWidgets('peeking leaves no read, typing, presence or key signal', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final room = client.getRoomById(_roomId)!;
    expect(room.markedUnread, isTrue);
    FakeMatrixApi.calledEndpoints.clear();

    await tester.longPress(row);
    await settle(tester);
    expect(find.text(notice), findsOneWidget);
    expect(find.text('first message'), findsOneWidget);
    expect(find.text('mine'), findsOneWidget);
    expect(
      find.text('second <b>message</b>'),
      findsOneWidget,
      reason: 'markup stays literal',
    );

    await tester.drag(find.text('first message'), const Offset(0, 40));
    await sync(tester, [message('4', 'a new one')]);
    await settle(tester);
    expect(find.text('a new one'), findsOneWidget);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await settle(tester);

    await tester.tapAt(const Offset(390, 790));
    await settle(tester);
    expect(find.text(notice), findsNothing);

    await tester.longPress(row);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text(notice), findsNothing);

    await tester.longPress(row);
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text(notice), findsNothing);

    expect(forbidden(), isEmpty);
    expect(room.markedUnread, isTrue);
    expect(room.notificationCount, 2);
    expect(find.byType(ChatPageWithRoom), findsNothing);
    await finish(tester);
  });

  testWidgets('after peeking the row still opens the chat, and the card does '
      'too', (tester) async {
    await pumpApp(tester);
    await tester.longPress(row);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text(notice), findsNothing);
    await tester.tap(row);
    await settle(tester);
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.path,
      '/rooms/$_roomId',
    );
    FluffyChatApp.router.go('/rooms');
    await settle(tester);
    await tester.longPress(row);
    await settle(tester);
    await tester.tap(find.text(notice));
    await settle(tester);
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.path,
      '/rooms/$_roomId',
    );
    await finish(tester);
  });

  testWidgets('dismissing with a tap on the scrim leaves the row tappable', (
    tester,
  ) async {
    await pumpApp(tester);
    for (var i = 0; i < 2; i++) {
      await tester.longPress(row);
      await settle(tester);
      expect(find.text(notice), findsOneWidget);
      await tester.tapAt(const Offset(390, 790));
      await settle(tester);
      expect(find.text(notice), findsNothing);
    }
    await tester.tap(row);
    await settle(tester);
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.path,
      '/rooms/$_roomId',
    );
    await finish(tester);
  });

  testWidgets('the menu labels follow the room while the peek is open', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.longPress(row);
    await settle(tester);
    expect(find.text('Mark as read'), findsOneWidget);
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'peekread${syncs++}',
          rooms: RoomsUpdate(
            join: {
              _roomId: JoinedRoomUpdate(
                unreadNotifications: UnreadNotificationCounts(
                  notificationCount: 0,
                ),
                accountData: [
                  BasicEvent(
                    type: 'm.marked_unread',
                    content: {'unread': false},
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Mark as read'), findsNothing);
    expect(find.text('Mark as unread'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('an entry whose state changed behind the label does nothing', (
    tester,
  ) async {
    await pumpApp(tester);
    final room = client.getRoomById(_roomId)!;
    await tester.longPress(row);
    await settle(tester);
    expect(find.text('Mark as read'), findsOneWidget);
    room.notificationCount = 0;
    room.roomAccountData.remove('m.marked_unread');
    expect(room.isUnread, isFalse);
    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.text('Mark as read'));
    await settle(tester);
    expect(
      FakeMatrixApi.calledEndpoints.keys.where(
        (path) =>
            path.contains('/read_markers') || path.contains('marked_unread'),
      ),
      isEmpty,
      reason: '"Mark as read" must never mark a read chat unread',
    );
    await finish(tester);
  });

  testWidgets('Mark as read in the menu is the only marker path', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.longPress(row);
    await settle(tester);
    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.text('Mark as read'));
    await settle(tester);
    expect(
      FakeMatrixApi.calledEndpoints.keys.where(
        (path) => path.contains('/read_markers'),
      ),
      ['/client/v3/rooms/$_roomPath/read_markers'],
    );
    expect(find.text(notice), findsNothing);
    await finish(tester);
  });

  testWidgets('the menu runs the row actions', (tester) async {
    await pumpApp(tester);
    expect(PeekMenuItem.values.length, 6);
    await tester.longPress(row);
    await settle(tester);
    for (final label in [
      'Mark as read',
      'Pin',
      'Mute',
      'Archive',
      'Leave chat',
      'More options',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.text('Pin'));
    await settle(tester);
    expect(
      FakeMatrixApi.calledEndpoints.keys.where(
        (path) => path.contains('/tags/'),
      ),
      ['/client/v3/user/$_user/rooms/$_roomPath/tags/m.favourite'],
    );
    FakeMatrixApi.calledEndpoints.clear();
    await tester.longPress(row);
    await settle(tester);
    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(
      FakeMatrixApi.calledEndpoints.keys.where(
        (path) => path.contains('/tags/im.fluffychat.archived'),
      ),
      ['/client/v3/user/$_user/rooms/$_roomPath/tags/im.fluffychat.archived'],
    );
    await finish(tester);
  });

  testWidgets('Leave chat asks first', (tester) async {
    await pumpApp(tester);
    await tester.longPress(row);
    await settle(tester);
    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.text('Leave chat'));
    await settle(tester);
    expect(find.text('Are you sure?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(
      FakeMatrixApi.calledEndpoints.keys.where(
        (path) => path.contains('/leave'),
      ),
      isEmpty,
    );
    await finish(tester);
  });

  testWidgets('right click keeps the old menu, the semantics action peeks', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(row, buttons: kSecondaryButton);
    await settle(tester);
    expect(find.text(notice), findsNothing);
    expect(find.text('Mark as unread'), findsNothing);
    expect(find.text('Archive'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);

    final handle = tester.ensureSemantics();
    final node = find.semantics.byLabel(RegExp('^Anna')).evaluate().single;
    final peekId = {
      for (final id in node.getSemanticsData().customSemanticsActionIds!)
        CustomSemanticsAction.getAction(id)!.label: id,
    }['Peek'];
    tester.semantics.performAction(
      find.semantics.byLabel(RegExp('^Anna')),
      SemanticsAction.customAction,
      args: peekId,
    );
    await settle(tester);
    expect(find.text(notice), findsOneWidget);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('the scrim blurs, unless transparency is reduced', (
    tester,
  ) async {
    await pumpApp(tester);
    final before = find.byType(BackdropFilter).evaluate().length;
    await tester.longPress(row);
    await settle(tester);
    expect(
      find.byType(BackdropFilter).evaluate().length,
      greaterThan(before),
      reason: 'scrim and menu blur',
    );
    await tester.tapAt(const Offset(390, 790));
    await settle(tester);

    await AppSettings.reduceTransparency.setItem(true);
    addTearDown(() => AppSettings.reduceTransparency.setItem(false));
    await tester.pump();
    await tester.longPress(row);
    await settle(tester);
    expect(find.text(notice), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    await finish(tester);
  });
  testWidgets('goldens: light, dark and RTL', (tester) async {
    await sync(
      tester,
      [
        message(
          'g1',
          'Are we still on for tonight?',
          sender: '@bob:example.org',
        ),
        message('g2', 'Yes, see you at 8'),
        message('g3', 'Great, I will bring the notes', sender: client.userID),
      ],
      first: true,
      roomId: '!peekgold:x',
    );
    final room = client.getRoomById('!peekgold:x')!;
    for (final variant in goldenVariants) {
      await pumpGoldenWidget(
        tester,
        Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => showPeek(
                context,
                room,
                onSelect: (_, _) {},
                onOpenChat: () {},
              ),
            );
            return const SizedBox.expand();
          },
        ),
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: const Locale('en'),
        size: const Size(400, 700),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      await tester.loadAssets();
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/peek_${variant.suffix}.png'),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('large text does not overflow the peek', (tester) async {
    await pumpApp(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.longPress(row);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Leave chat'), findsOneWidget);
    await finish(tester);
  });
}
