// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

const _peer = '@alice:example.com';
const _newRoomId = '!1234:fakeServer.notExisting';

/// The new message page runs the real `Client.startDirectChat` of the SDK
/// (through the user dialog), with default options. The SDK adds
/// `m.room.encryption` to the initial state list it is handed, so a list that
/// cannot grow breaks chat creation only when the real call runs.
void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.onRequest = null;
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': <Object?>[],
      'limited': false,
    };
  });
  tearDown(harness.tearDown);

  Map<Object?, Object?> body() {
    final posts = api.requests('/createRoom', method: 'POST');
    expect(posts, hasLength(1));
    return posts.single.json! as Map;
  }

  testWidgets('searching an id, opening the profile and starting the chat', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    harness.client.rooms.add(
      Room(id: _newRoomId, client: harness.client, membership: Membership.join),
    );
    await tester.enterText(find.byKey(NewPrivateChatView.fieldKey), _peer);
    await tester.pump(const Duration(milliseconds: 600));
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.text('alice'));
    await harness.settle(tester, rounds: 3);
    final l10n = L10n.of(tester.element(find.byType(NewPrivateChat)));
    await tester.tap(find.text(l10n.createNewChat));
    await harness.settle(tester, rounds: 8);
    final request = body();
    expect(request['is_direct'], isTrue);
    expect(request['invite'], [_peer]);
    final state = ((request['initial_state'] ?? <Object?>[]) as List)
        .cast<Map<Object?, Object?>>();
    expect(state.where((e) => e['type'] == 'm.room.encryption'), hasLength(1));
    expect(api.requests('/join/', method: 'POST'), isEmpty);
    expect(
      FluffyChatApp.router.routeInformationProvider.value.uri.path,
      '/rooms/$_newRoomId',
    );
    await harness.finish(tester);
  });

  testWidgets('nothing is created before the button of the dialog is tapped', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    await tester.enterText(find.byKey(NewPrivateChatView.fieldKey), _peer);
    await tester.pump(const Duration(milliseconds: 600));
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.text('alice'));
    await harness.settle(tester, rounds: 3);
    expect(api.requests('/createRoom', method: 'POST'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets(
    'New group goes through the real createGroupChat with default options',
    (tester) async {
      await harness.open(tester, path: '/rooms/newgroup');
      harness.client.rooms.add(
        Room(
          id: _newRoomId,
          client: harness.client,
          membership: Membership.join,
        ),
      );
      final l10n = L10n.of(tester.element(find.byType(Scaffold).first));
      await tester.enterText(find.byType(TextField).first, 'Project room');
      await tester.tap(
        find.widgetWithText(ElevatedButton, l10n.createGroupAndInviteUsers),
      );
      await harness.settle(tester, rounds: 8);
      final request = body();
      final state = ((request['initial_state'] ?? <Object?>[]) as List)
          .cast<Map<Object?, Object?>>();
      expect(
        state.where((e) => e['type'] == 'm.room.encryption'),
        hasLength(1),
      );
      expect(request['name'], 'Project room');
      await harness.finish(tester);
    },
  );
}
