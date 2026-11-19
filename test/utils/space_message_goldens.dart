// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/new_private_chat/new_private_chat.dart';

import 'chat_page_harness.dart';
import 'golden.dart';
import 'recording_api.dart';

const _space = '!space:example.org';
const _news = '!news:example.org';
const _general = '!general:example.org';
const _help = '!help:example.org';
const _sub = '!sub:example.org';

Map<String, Object?> entry(
  String id,
  String name, {
  String? type,
  int members = 12,
}) => {
  'room_id': id,
  'name': name,
  'room_type': type,
  'num_joined_members': members,
  'children_state': type == null ? <Object?>[] : [{}, {}, {}],
  'guest_can_join': false,
  'world_readable': false,
};

/// Registers the golden tests of the space overview, the community, the new
/// message page and the scan confirmation for [variants]. Arabic runs in its
/// own file: after other app tests in the same file the app stays empty (W03
/// m10).
void registerSpaceMessageGoldens(List<GoldenVariant> variants) {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  BasicEvent? savedDirect;

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    harness.resetRooms();
    api.clear();
    savedDirect = harness.client.accountData['m.direct'];
    api.getResponder = (url) => url.path.endsWith('/hierarchy')
        ? {
            'rooms': [
              entry(_space, 'Berlin Makers', type: 'm.space'),
              entry(_news, 'Announcements'),
              entry(_general, 'General', members: 1204),
              entry(_help, 'Help desk', members: 640),
              entry(_sub, 'Translations', type: 'm.space'),
            ],
          }
        : null;
  });
  tearDown(() async {
    final saved = savedDirect;
    if (saved != null) harness.client.accountData['m.direct'] = saved;
    harness.client.presences.clear();
    await harness.tearDown();
  });

  void state(
    Room room,
    String type,
    Map<String, Object?> content, {
    String key = '',
  }) => room.setState(
    Event(
      type: type,
      stateKey: key,
      content: content,
      room: room,
      eventId: '\$$type${room.id}$key',
      senderId: '@admin:example.org',
      originServerTs: DateTime(2030),
    ),
  );

  Room addSpace() {
    final room = Room(
      id: _space,
      client: harness.client,
      membership: Membership.join,
    );
    state(room, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
    state(room, EventTypes.RoomName, {'name': 'Berlin Makers'});
    state(room, EventTypes.RoomTopic, {
      'topic': 'Workshops, projects and a lot of solder.',
    });
    state(room, EventTypes.RoomPowerLevels, {
      'users': {harness.client.userID ?? '': 100},
      'state_default': 50,
    });
    for (final child in [_news, _general, _help, _sub]) {
      state(room, EventTypes.SpaceChild, {
        'via': ['example.org'],
        if (child == _help) 'suggested': true,
      }, key: child);
    }
    harness.client.rooms.add(room);
    return room;
  }

  Room addGroup(
    String id,
    String name,
    Map<String, Object?> levels, {
    String? last,
  }) {
    final room = Room(
      id: id,
      client: harness.client,
      membership: Membership.join,
    );
    state(room, EventTypes.RoomName, {'name': name});
    state(room, EventTypes.RoomPowerLevels, levels);
    if (last != null) {
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': last},
        room: room,
        eventId: '\$last$id',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2031, 6, 15, 10, 2),
      );
    }
    harness.client.rooms.add(room);
    return room;
  }

  final spacePath = '/rooms/space/${Uri.encodeComponent(_space)}';

  for (final variant in variants) {
    testWidgets('space overview golden ${variant.suffix}', (tester) async {
      addSpace();
      addGroup(_general, 'General', {'events_default': 0});
      addGroup(_news, 'Announcements', {'events_default': 0});
      await harness.open(
        tester,
        path: spacePath,
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      await harness.settle(tester, rounds: 6);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/space_overview_${variant.suffix}.png'),
      );
      await harness.finish(tester);
    });
  }

  for (final variant in variants) {
    testWidgets('community golden ${variant.suffix}', (tester) async {
      addSpace();
      addGroup(_general, 'General', {'events_default': 0});
      addGroup(
        _news,
        'Announcements',
        {
          'events_default': 100,
          'users_default': 0,
          'users': {harness.client.userID ?? '': 0},
        },
        last:
            'Saturday workshop moved to the big room. Bring your own soldering iron.',
      );
      await harness.open(
        tester,
        path: spacePath,
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      await harness.settle(tester, rounds: 6);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/community_${variant.suffix}.png'),
      );
      await harness.finish(tester);
    });
  }

  for (final variant in variants) {
    testWidgets('new message golden ${variant.suffix}', (tester) async {
      final client = harness.client;
      for (final (id, _, name) in [
        ('!d1:example.org', '@mara:example.org', 'Mara Lindqvist'),
        ('!d2:example.org', '@kim:example.org', 'Kim Sato'),
      ]) {
        final room = Room(id: id, client: client, membership: Membership.join);
        state(room, EventTypes.RoomName, {'name': name});
        client.rooms.add(room);
      }
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@mara:example.org': ['!d1:example.org'],
          '@kim:example.org': ['!d2:example.org'],
        },
      );
      client.presences['@mara:example.org'] = CachedPresence.fromJson({
        'user_id': '@mara:example.org',
        'presence': 'online',
        'last_active_timestamp': DateTime(2031, 6, 15).millisecondsSinceEpoch,
        'status_msg': 'Working on the redesign',
      });
      await harness.open(
        tester,
        path: '/rooms/newprivatechat',
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      await harness.settle(tester, rounds: 6);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/new_message_${variant.suffix}.png'),
      );
      await harness.finish(tester);
    });
  }

  for (final variant in variants) {
    testWidgets('scan confirmation golden ${variant.suffix}', (tester) async {
      await harness.open(
        tester,
        path: '/rooms/newprivatechat',
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      final controller = tester.state<NewPrivateChatController>(
        find.byType(NewPrivateChat),
      );
      unawaited(
        controller.handleScan(
          'https://matrix.to/#/!room:example.org?via=example.org&via=other.example',
        ),
      );
      await harness.settle(tester, rounds: 3);
      await harness.settle(tester, rounds: 6);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/scan_confirm_sheet_${variant.suffix}.png'),
      );
      await harness.finish(tester);
    });
  }
}
