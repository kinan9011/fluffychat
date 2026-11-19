// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_header.dart';
import 'package:fluffychat/pages/chat_list/active_call_indicator.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pulsating_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(() async {
    harness.room.states.remove(MatrixRtcCallMember.eventType);
    await harness.tearDown();
  });

  void startCall(Room room) {
    room.setState(
      Event(
        type: MatrixRtcCallMember.eventType,
        stateKey: '_@bob:example.org_D_m.call',
        senderId: '@bob:example.org',
        eventId: '\$call:example.org',
        originServerTs: DateTime.now(),
        room: room,
        content: {
          'application': 'm.call',
          'call_id': '',
          'device_id': 'D',
          'expires': 86400000,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'foci_preferred': [
            {
              'type': 'livekit',
              'livekit_service_url': 'https://lk.example',
              'livekit_alias': room.id,
            },
          ],
          'focus_active': {
            'type': 'livekit',
            'focus_selection': 'oldest_membership',
          },
          'm.call.intent': 'video',
        },
      ),
    );
  }

  MatrixState matrixOf(WidgetTester tester) =>
      tester.state<MatrixState>(find.byType(Matrix));

  Future<void> load(WidgetTester tester) async {
    final matrix = matrixOf(tester);
    await tester.runAsync(
      () => matrix.serverCapabilities.load(harness.room.client, force: true),
    );
    await harness.settle(tester, rounds: 2);
  }

  Future<void> openOverflow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 2);
  }

  Finder headerPill() => find.descendant(
    of: find.byType(ChatHeader),
    matching: find.byType(PulsatingWidget),
  );

  for (final size in [const Size(360, 640), const Size(1200, 900)]) {
    group('${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('a server with calls shows the active call pill', (
        tester,
      ) async {
        startCall(harness.room);
        await harness.open(tester, width: size.width, height: size.height);
        await load(tester);
        expect(headerPill(), findsOneWidget);
        if (size.width > 900) {
          expect(find.byType(ActiveCallIndicator), findsOneWidget);
        }
        await harness.finish(tester);
      });

      testWidgets('a server with calls offers a video call in the menu', (
        tester,
      ) async {
        await harness.open(tester, width: size.width, height: size.height);
        await load(tester);
        await openOverflow(tester);
        expect(find.text('Video call'), findsOneWidget);
        await harness.finish(tester);
      });

      testWidgets('a server without calls shows nothing call related', (
        tester,
      ) async {
        harness.capabilities.set(harness.room.client, supported: false);
        startCall(harness.room);
        await harness.open(tester, width: size.width, height: size.height);
        await load(tester);
        expect(headerPill(), findsNothing);
        expect(find.byType(ActiveCallIndicator), findsNothing);
        await harness.finish(tester);
      });

      testWidgets('the menu has no video call without a server for it', (
        tester,
      ) async {
        harness.capabilities.set(harness.room.client, supported: false);
        await harness.open(tester, width: size.width, height: size.height);
        await load(tester);
        await openOverflow(tester);
        expect(find.text('Video call'), findsNothing);
        expect(find.byIcon(Icons.videocam_rounded), findsNothing);
        await harness.finish(tester);
      });

      testWidgets('the pill follows the capability live', (tester) async {
        startCall(harness.room);
        await harness.open(tester, width: size.width, height: size.height);
        await load(tester);
        expect(headerPill(), findsOneWidget);
        harness.capabilities.set(harness.room.client, supported: false);
        await load(tester);
        expect(headerPill(), findsNothing);
        harness.capabilities.set(harness.room.client, supported: true);
        await load(tester);
        expect(headerPill(), findsOneWidget);
        await harness.finish(tester);
      });
    });
  }

  testWidgets('?action=call does nothing on a server without calls', (
    tester,
  ) async {
    harness.capabilities.set(harness.room.client, supported: false);
    await harness.open(tester, path: '/rooms/${harness.room.id}?action=call');
    await load(tester);
    expect(matrixOf(tester).activeCallRoomId.value, isNull);
    await harness.finish(tester);
  });

  testWidgets('?action=call starts the call on a server with calls', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/${harness.room.id}');
    final matrix = matrixOf(tester);
    final started = <String?>[];
    matrix.activeCallRoomId.addListener(() {
      started.add(matrix.activeCallRoomId.value);
      matrix.activeCallRoomId.value = null;
    });
    FluffyChatApp.router.go('/rooms/${harness.room.id}?action=call');
    await harness.settle(tester, rounds: 3);
    await load(tester);
    expect(started, contains(harness.room.id));
    await harness.finish(tester);
  });

  testWidgets('startOrJoinVideoCall is blocked without calls', (tester) async {
    harness.capabilities.set(harness.room.client, supported: false);
    await harness.open(tester);
    await load(tester);
    tester
        .state<ChatController>(find.byType(ChatPageWithRoom))
        .startOrJoinVideoCall();
    expect(matrixOf(tester).activeCallRoomId.value, isNull);
    await harness.finish(tester);
  });

  testWidgets('joinCall is blocked without calls and works with them', (
    tester,
  ) async {
    harness.capabilities.set(harness.room.client, supported: false);
    await harness.open(tester);
    await load(tester);
    final matrix = matrixOf(tester);
    final joined = await tester.runAsync(
      () => matrix.joinCall(harness.room.client, harness.room.id),
    );
    await harness.settle(tester, rounds: 2);
    expect(joined, isFalse);
    expect(matrix.activeCallRoomId.value, isNull);
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.toString(),
      isNot(contains('action=call')),
    );
    await harness.finish(tester);
  });

  group('a ring in a room with a running call', () {
    Event ring() => Event(
      type: RtcNotificationContent.eventType,
      content: {
        'sender_ts': DateTime.now().millisecondsSinceEpoch,
        'notification_type': 'ring',
        'm.mentions': {
          'user_ids': [harness.room.client.userID],
        },
      },
      room: harness.room,
      eventId: r'$ring:example.org',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now(),
    );

    Future<void> read(WidgetTester tester) async {
      startCall(harness.room);
      await harness.open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await load(tester);
      final controller = tester.state<ChatController>(
        find.byType(ChatPageWithRoom),
      );
      controller.timeline!.events.insert(0, ring());
      api.clear();
      controller.setReadMarker(eventId: ring().eventId);
      await harness.settle(tester, rounds: 3);
    }

    testWidgets('with calls the marker is held back (mutes CallKit)', (
      tester,
    ) async {
      await read(tester);
      expect(api.requests('/read_markers'), isEmpty);
      await harness.finish(tester);
    });

    testWidgets('without calls the ring is read like any event', (
      tester,
    ) async {
      harness.capabilities.set(harness.room.client, supported: false);
      await read(tester);
      expect(api.requests('/read_markers'), isNotEmpty);
      await harness.finish(tester);
    });
  });

  testWidgets('turning calls off ends the call that is running', (
    tester,
  ) async {
    await harness.open(tester);
    final matrix = matrixOf(tester);
    matrix.activeCallRoomId.value = harness.room.id;
    await AppSettings.callsEnabled.setItem(false);
    expect(matrix.activeCallRoomId.value, isNull);
    await AppSettings.callsEnabled.setItem(true);
    expect(matrix.activeCallRoomId.value, isNull);
    await harness.finish(tester);
  });

  testWidgets('a call keeps running while the setting stays on', (
    tester,
  ) async {
    await harness.open(tester);
    final matrix = matrixOf(tester);
    matrix.activeCallRoomId.value = harness.room.id;
    await AppSettings.callsEnabled.setItem(true);
    expect(matrix.activeCallRoomId.value, harness.room.id);
    matrix.activeCallRoomId.value = null;
    await harness.finish(tester);
  });
}
