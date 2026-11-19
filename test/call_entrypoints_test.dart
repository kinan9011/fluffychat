// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> load(WidgetTester tester) async {
    final matrix = tester.state<MatrixState>(find.byType(Matrix));
    await tester.runAsync(
      () => matrix.serverCapabilities.load(harness.room.client, force: true),
    );
    await harness.settle(tester, rounds: 2);
  }

  group('group call permission row', () {
    testWidgets('is listed on a server with calls', (tester) async {
      await harness.open(
        tester,
        path: '/rooms/${harness.room.id}/details/permissions',
      );
      await load(tester);
      expect(find.text('Create or join a group call'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('is not listed without calls, and follows live', (
      tester,
    ) async {
      harness.capabilities.set(harness.room.client, supported: false);
      await harness.open(
        tester,
        path: '/rooms/${harness.room.id}/details/permissions',
      );
      await load(tester);
      expect(find.text('Create or join a group call'), findsNothing);
      harness.capabilities.set(harness.room.client, supported: true);
      await load(tester);
      expect(find.text('Create or join a group call'), findsOneWidget);
      await harness.finish(tester);
    });
  });

  group('a stored group call power level', () {
    void store(Room room) {
      final old = room.getState(EventTypes.RoomPowerLevels);
      final content = {...?old?.content};
      content['events'] = {
        ...?(content['events'] as Map<String, Object?>?),
        MatrixRtcCallMember.eventType: 50,
      };
      room.setState(
        Event(
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: '@bob:example.org',
          eventId: r'$levels:example.org',
          originServerTs: DateTime.now(),
          room: room,
          content: content,
        ),
      );
      addTearDown(() {
        if (old == null) {
          room.states.remove(EventTypes.RoomPowerLevels);
          return;
        }
        room.setState(old);
      });
    }

    testWidgets('is hidden without calls, and stays stored', (tester) async {
      store(harness.room);
      harness.capabilities.set(harness.room.client, supported: false);
      await harness.open(
        tester,
        path: '/rooms/${harness.room.id}/details/permissions',
      );
      await load(tester);
      expect(find.text('Create or join a group call'), findsNothing);
      final events =
          harness.room.getState(EventTypes.RoomPowerLevels)!.content['events']!
              as Map<String, Object?>;
      expect(events[MatrixRtcCallMember.eventType], 50);
      await harness.finish(tester);
    });

    testWidgets('is shown with calls', (tester) async {
      store(harness.room);
      await harness.open(
        tester,
        path: '/rooms/${harness.room.id}/details/permissions',
      );
      await load(tester);
      expect(find.text('Create or join a group call'), findsOneWidget);
      await harness.finish(tester);
    });
  });

  group('no call icon anywhere on a server without calls', () {
    const icons = [
      Icons.call,
      Icons.call_outlined,
      Icons.call_rounded,
      Icons.videocam,
      Icons.videocam_outlined,
      Icons.videocam_rounded,
      Icons.video_call_outlined,
      Icons.add_call,
    ];

    for (final path in ['/profile', '/settings', '/settings/homeserver']) {
      testWidgets('$path has no call button', (tester) async {
        harness.capabilities.set(harness.room.client, supported: false);
        await harness.open(tester, path: path);
        await load(tester);
        for (final icon in icons) {
          expect(find.byIcon(icon), findsNothing, reason: icon.toString());
        }
        await harness.finish(tester);
      });
    }

    testWidgets('the chat details page has no call button', (tester) async {
      harness.capabilities.set(harness.room.client, supported: false);
      await harness.open(tester, path: '/rooms/${harness.room.id}/details');
      await load(tester);
      for (final icon in icons) {
        expect(find.byIcon(icon), findsNothing, reason: icon.toString());
      }
      await harness.finish(tester);
    });
  });
}
