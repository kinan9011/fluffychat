// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: deprecated_member_use

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  late BasicEvent? savedDirect;

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.onRequest = null;
    savedDirect = harness.client.accountData['m.direct'];
    harness.client.presences.clear();
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': [
        {'user_id': '@carol:example.org', 'display_name': 'Carol'},
      ],
      'limited': false,
    };
  });
  tearDown(() async {
    final saved = savedDirect;
    if (saved != null) harness.client.accountData['m.direct'] = saved;
    harness.client.presences.clear();
    await harness.tearDown();
  });

  void direct(Map<String, String> userToRoom) {
    final client = harness.client;
    harness.resetRooms();
    for (final entry in userToRoom.entries) {
      final room = Room(
        id: entry.value,
        client: client,
        membership: Membership.join,
      );
      room.setState(
        Event(
          type: EventTypes.RoomName,
          stateKey: '',
          content: {'name': 'Chat with ${entry.key}'},
          room: room,
          eventId: '\$name${entry.value}',
          senderId: '@admin:example.org',
          originServerTs: DateTime(2030),
        ),
      );
      client.rooms.add(room);
    }
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        for (final entry in userToRoom.entries) entry.key: [entry.value],
      },
    );
  }

  void presence(
    String id,
    PresenceType type, {
    DateTime? seen,
    String? status,
  }) {
    harness.client.presences[id] = CachedPresence.fromJson({
      'user_id': id,
      'presence': type.name,
      'last_active_timestamp': ?seen?.millisecondsSinceEpoch,
      'status_msg': ?status,
    });
  }

  String location() =>
      FluffyChatApp.router.routeInformationProvider.value.uri.toString();

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(NewPrivateChat)));

  testWidgets('the actions are New group, New space, Share my invite link', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    expect(find.byKey(NewPrivateChatView.newGroupKey), findsOneWidget);
    expect(find.byKey(NewPrivateChatView.newSpaceKey), findsOneWidget);
    expect(find.byKey(NewPrivateChatView.inviteKey), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('New group and New space open their pages', (tester) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    await tester.tap(find.byKey(NewPrivateChatView.newGroupKey));
    await harness.settle(tester, rounds: 3);
    expect(Uri.parse(location()).path, '/rooms/newgroup');
    await harness.finish(tester);
  });

  testWidgets('Cancel leaves the page', (tester) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    await tester.tap(find.byKey(NewPrivateChatView.cancelKey));
    await harness.settle(tester, rounds: 3);
    expect(Uri.parse(location()).path, '/rooms');
    await harness.finish(tester);
  });

  testWidgets(
    'contacts: those seen last come first, from cached presence only',
    (tester) async {
      direct({
        '@old:example.org': '!old:example.org',
        '@new:example.org': '!new:example.org',
        '@unknown:example.org': '!unknown:example.org',
      });
      presence(
        '@old:example.org',
        PresenceType.offline,
        seen: DateTime(2031, 1, 1),
      );
      presence(
        '@new:example.org',
        PresenceType.online,
        seen: DateTime(2031, 6, 1),
      );
      await harness.open(tester, path: '/rooms/newprivatechat');
      final newer = tester.getTopLeft(find.text('Chat with @new:example.org'));
      final older = tester.getTopLeft(find.text('Chat with @old:example.org'));
      expect(newer.dy, lessThan(older.dy));
      expect(api.requests('/presence/'), isEmpty);
      expect(find.text(l10n(tester).newMessageContacts), findsOneWidget);
      await harness.finish(tester);
    },
  );

  testWidgets('no contacts: no contacts header', (tester) async {
    direct({});
    await harness.open(tester, path: '/rooms/newprivatechat');
    expect(find.text(l10n(tester).newMessageContacts), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a status text is shown cleaned', (tester) async {
    direct({'@a:example.org': '!a:example.org'});
    presence(
      '@a:example.org',
      PresenceType.online,
      status: 'In a\u202E meeting\u200B',
    );
    await harness.open(tester, path: '/rooms/newprivatechat');
    expect(find.textContaining('\u202E'), findsNothing);
    expect(find.textContaining('\u200B'), findsNothing);
    expect(find.textContaining('meeting'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('the directory is searched after the cool down', (tester) async {
    await harness.open(tester, path: '/rooms/newprivatechat');
    api.clear();
    await tester.enterText(find.byKey(NewPrivateChatView.fieldKey), 'car');
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.requests('user_directory/search', method: 'POST'), isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await harness.settle(tester, rounds: 3);
    expect(api.requests('user_directory/search', method: 'POST'), hasLength(1));
    expect(find.text('Carol'), findsOneWidget);
    expect(api.requests('/presence/'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets(
    'a typed Matrix id is offered even if the directory does not know it',
    (tester) async {
      await harness.open(tester, path: '/rooms/newprivatechat');
      await tester.enterText(
        find.byKey(NewPrivateChatView.fieldKey),
        '@dave:example.org',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await harness.settle(tester, rounds: 3);
      expect(find.text('@dave:example.org'), findsWidgets);
      await harness.finish(tester);
    },
  );

  testWidgets('a name from the directory is shown cleaned', (tester) async {
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': [
        {'user_id': '@evil:example.org', 'display_name': 'Ev\u202Eil\u200B'},
      ],
      'limited': false,
    };
    await harness.open(tester, path: '/rooms/newprivatechat');
    await tester.enterText(find.byKey(NewPrivateChatView.fieldKey), 'evil');
    await tester.pump(const Duration(milliseconds: 600));
    await harness.settle(tester, rounds: 3);
    expect(find.textContaining('\u202E'), findsNothing);
    expect(find.textContaining('\u200B'), findsNothing);
    await harness.finish(tester);
  });
}
