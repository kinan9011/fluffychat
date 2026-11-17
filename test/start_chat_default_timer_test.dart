// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

const _peer = '@alice:example.com';
const _newRoomId = '!1234:fakeServer.notExisting';

/// These tests run the real `Client.startDirectChat` and
/// `Client.createGroupChat` of the SDK. The SDK adds `m.room.encryption` to the
/// `initialState` list it is handed, so a list that cannot grow breaks chat
/// creation only when the real call runs.
void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.getOverrides.clear();
    api.onRequest = null;
  });
  tearDown(harness.tearDown);

  Map<Object?, Object?> createRoomBody() {
    final posts = api.requests('/createRoom', method: 'POST');
    expect(posts, hasLength(1));
    return posts.single.json! as Map;
  }

  List<Map<Object?, Object?>> initialState() =>
      ((createRoomBody()['initial_state'] ?? <Object?>[]) as List)
          .cast<Map<Object?, Object?>>();

  Iterable<Map<Object?, Object?>> ofType(String type) =>
      initialState().where((event) => event['type'] == type);

  void joinNewRoom() {
    harness.client.rooms.removeWhere((room) => room.id == _newRoomId);
    harness.client.rooms.add(
      Room(id: _newRoomId, client: harness.client, membership: .join),
    );
  }

  Future<void> startDirectChat(WidgetTester tester) async {
    await harness.open(tester, path: '/settings');
    joinNewRoom();
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      UserDialog.show(
        context: context,
        profile: Profile(userId: _peer, displayName: 'Peer'),
      ),
    );
    await harness.settle(tester);
    await tester.tap(find.text(L10n.of(context).createNewChat));
    await harness.settle(tester, rounds: 8);
  }

  group('starting a direct chat from the user dialog', () {
    testWidgets('default timer Off: the encrypted chat is still created', (
      tester,
    ) async {
      await startDirectChat(tester);
      expect(ofType('m.room.encryption'), hasLength(1));
      expect(ofType('m.room.retention'), isEmpty);
      await harness.finish(tester);
    });

    testWidgets('timer On: encryption and the retention state are both sent', (
      tester,
    ) async {
      await AppSettings.defaultDisappearSeconds.setItem(604800);
      api.getOverrides['/client/versions'] = {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc1763': true},
      };
      await startDirectChat(tester);
      expect(ofType('m.room.encryption'), hasLength(1));
      final retention = ofType('m.room.retention');
      expect(retention, hasLength(1));
      expect(retention.single['content'], {
        'max_lifetime': 604800000,
        'expire_on_clients': true,
      });
      await harness.finish(tester);
    });

    testWidgets('timer On, server without retention: encryption only', (
      tester,
    ) async {
      await AppSettings.defaultDisappearSeconds.setItem(604800);
      await startDirectChat(tester);
      expect(ofType('m.room.encryption'), hasLength(1));
      expect(ofType('m.room.retention'), isEmpty);
      await harness.finish(tester);
    });
  });

  Future<void> openNewChatPage(
    WidgetTester tester,
    String path,
    String Function(L10n l10n) button,
  ) async {
    await harness.open(tester, path: path);
    joinNewRoom();
    final l10n = L10n.of(tester.element(find.byType(Scaffold).first));
    await tester.enterText(find.byType(TextField).first, 'Project room');
    await tester.tap(find.widgetWithText(ElevatedButton, button(l10n)));
    await harness.settle(tester, rounds: 8);
  }

  group('creating a group from the new group page', () {
    testWidgets('default timer Off: encryption, no retention', (tester) async {
      await openNewChatPage(
        tester,
        '/rooms/newgroup',
        (l10n) => l10n.createGroupAndInviteUsers,
      );
      expect(ofType('m.room.encryption'), hasLength(1));
      expect(ofType('m.room.retention'), isEmpty);
      await harness.finish(tester);
    });

    testWidgets('timer On: encryption and retention are both sent', (
      tester,
    ) async {
      await AppSettings.defaultDisappearSeconds.setItem(86400);
      api.getOverrides['/client/versions'] = {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc1763': true},
      };
      await openNewChatPage(
        tester,
        '/rooms/newgroup',
        (l10n) => l10n.createGroupAndInviteUsers,
      );
      expect(ofType('m.room.encryption'), hasLength(1));
      expect(ofType('m.room.retention').single['content'], {
        'max_lifetime': 86400000,
        'expire_on_clients': true,
      });
      await harness.finish(tester);
    });
  });

  group('creating a space', () {
    testWidgets('never gets the default timer, with the timer On', (
      tester,
    ) async {
      await AppSettings.defaultDisappearSeconds.setItem(86400);
      await openNewChatPage(
        tester,
        '/rooms/newspace',
        (l10n) => l10n.createNewSpace,
      );
      expect(createRoomBody()['name'], 'Project room');
      expect(ofType('m.room.retention'), isEmpty);
      await harness.finish(tester);
    });
  });
}
