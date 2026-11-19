// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/space_overview/community_widgets.dart';
import 'package:odango/pages/space_overview/space_overview.dart';
import 'package:odango/pages/space_overview/space_overview_widgets.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

const _space = '!space:example.org';
const _news = '!news:example.org';
const _general = '!general:example.org';

Map<String, Object?> entry(String id, String name, {String? type}) => {
  'room_id': id,
  'name': name,
  'room_type': type,
  'num_joined_members': 7,
  'children_state': <Object?>[],
  'guest_can_join': false,
  'world_readable': false,
};

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  final clipboard = <String>[];

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.onRequest = null;
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    api.getResponder = (url) => url.path.endsWith('/hierarchy')
        ? {
            'rooms': [
              entry(_space, 'Berlin Makers', type: 'm.space'),
              entry(_news, 'Announcements'),
              entry(_general, 'General'),
            ],
          }
        : null;
    harness.resetRooms();
  });
  tearDown(harness.tearDown);

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

  Room addSpace({bool admin = false, String? alias}) {
    final room = Room(
      id: _space,
      client: harness.client,
      membership: Membership.join,
    );
    state(room, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
    state(room, EventTypes.RoomName, {'name': 'Berlin Makers'});
    if (alias != null) {
      state(room, EventTypes.RoomCanonicalAlias, {'alias': alias});
    }
    state(room, EventTypes.RoomPowerLevels, {
      'users': {harness.client.userID!: admin ? 100 : 0},
      'state_default': 50,
    });
    for (final child in [_news, _general]) {
      state(room, EventTypes.SpaceChild, {
        'via': ['example.org'],
      }, key: child);
    }
    harness.client.rooms.add(room);
    return room;
  }

  Room addGroup(
    String id, {
    required Map<String, Object?> levels,
    String? last,
    DateTime? at,
    Map<String, Object?>? retention,
  }) {
    final room = Room(
      id: id,
      client: harness.client,
      membership: Membership.join,
    );
    state(room, EventTypes.RoomPowerLevels, levels);
    if (retention != null) state(room, 'm.room.retention', retention);
    if (last != null) {
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': last},
        room: room,
        eventId: '\$last$id',
        senderId: '@admin:example.org',
        originServerTs: at ?? DateTime.now().subtract(const Duration(hours: 1)),
      );
    }
    harness.client.rooms.add(room);
    return room;
  }

  String path() => Uri(pathSegments: ['rooms', 'space', _space]).toString();

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(SpaceOverview, skipOffstage: false)));

  testWidgets('a space with an announcements room is shown as a community', (
    tester,
  ) async {
    addSpace(alias: '#makers:example.org');
    addGroup(
      _news,
      levels: announcementsLevelsFor(harness),
      last: 'Workshop moved',
    );
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    expect(find.byType(CommunityBanner), findsOneWidget);
    expect(find.byType(AnnouncementsCard), findsOneWidget);
    expect(find.text('Workshop moved'), findsOneWidget);
    expect(find.text(l10n(tester).communityOnlyModeratorsPost), findsOneWidget);
    expect(find.text(l10n(tester).communityGroups), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    await harness.finish(tester);
  });

  Room addRemote(String id) {
    final room = Room(
      id: id,
      client: harness.client,
      membership: Membership.join,
    );
    harness.client.rooms.add(room);
    return room;
  }

  void answerLevelsFor(Iterable<String> ids) {
    api.getResponder = (url) {
      if (url.path.endsWith('/hierarchy')) {
        return {
          'rooms': [
            entry(_space, 'Berlin Makers', type: 'm.space'),
            for (final id in ids) entry(id, 'Room $id'),
          ],
        };
      }
      if (url.path.contains('/state/m.room.power_levels')) {
        return announcementsLevelsFor(harness);
      }
      return null;
    };
  }

  List<RecordedRequest> levelRequests() =>
      api.requests('/state/m.room.power_levels', method: 'GET');

  testWidgets('a partial room is not post-loaded: only its power levels are '
      'asked, once', (tester) async {
    addSpace();
    const stored = '!stored:example.org';
    answerLevelsFor([stored]);
    final room = addRemote(stored);
    expect(room.partial, isTrue);
    await harness.open(tester, path: path());
    expect(find.byType(AnnouncementsCard), findsOneWidget);
    expect(room.partial, isTrue);
    expect(levelRequests(), hasLength(1));
    final controller = tester.state<SpaceOverviewController>(
      find.byType(SpaceOverview),
    );
    unawaited(controller.load(reset: true));
    await harness.settle(tester, rounds: 3);
    unawaited(controller.load(reset: true));
    await harness.settle(tester, rounds: 3);
    expect(levelRequests(), hasLength(1));
    await harness.finish(tester);
  });

  testWidgets('a room whose power levels are in memory is not asked', (
    tester,
  ) async {
    addSpace();
    addGroup(_news, levels: announcementsLevelsFor(harness));
    answerLevelsFor([_news]);
    await harness.open(tester, path: path());
    expect(find.byType(AnnouncementsCard), findsOneWidget);
    expect(levelRequests(), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('at most four power level requests are in flight', (
    tester,
  ) async {
    addSpace();
    final ids = [for (var n = 0; n < 12; n++) '!many$n:example.org'];
    answerLevelsFor(ids);
    ids.forEach(addRemote);
    var inFlight = 0;
    var peak = 0;
    final release = Completer<void>();
    api.onRequest = (request) async {
      if (!request.url.path.contains('/state/m.room.power_levels')) return;
      inFlight++;
      peak = inFlight > peak ? inFlight : peak;
      await release.future;
      inFlight--;
    };
    await harness.open(tester, path: path());
    expect(peak, 4);
    release.complete();
    await harness.settle(tester, rounds: 6);
    expect(levelRequests(), hasLength(12));
    expect(peak, 4);
    await harness.finish(tester);
  });

  testWidgets('power levels that are in neither memory nor database are asked '
      'from the server', (tester) async {
    addSpace();
    const remote = '!remote:example.org';
    api.getResponder = (url) {
      if (url.path.endsWith('/hierarchy')) {
        return {
          'rooms': [
            entry(_space, 'Berlin Makers', type: 'm.space'),
            entry(remote, 'Remote levels'),
          ],
        };
      }
      if (url.path.contains('/state/m.room.power_levels')) {
        return announcementsLevelsFor(harness);
      }
      return null;
    };
    harness.client.rooms.add(
      Room(id: remote, client: harness.client, membership: Membership.join),
    );
    await harness.open(tester, path: path());
    expect(find.byType(AnnouncementsCard), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a server that does not answer leaves the page working', (
    tester,
  ) async {
    addSpace();
    const remote = '!remote:example.org';
    api.getResponder = (url) => url.path.endsWith('/hierarchy')
        ? {
            'rooms': [
              entry(_space, 'Berlin Makers', type: 'm.space'),
              entry(remote, 'Remote levels'),
            ],
          }
        : null;
    api.onRequest = (request) async {
      if (request.url.path.contains('/state/m.room.power_levels')) {
        throw Exception('offline');
      }
    };
    harness.client.rooms.add(
      Room(id: remote, client: harness.client, membership: Membership.join),
    );
    await harness.open(tester, path: path());
    expect(find.byType(AnnouncementsCard), findsNothing);
    expect(find.text('Remote levels'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  testWidgets('no announcements room: a plain space', (tester) async {
    addSpace();
    addGroup(_news, levels: {'events_default': 0});
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    expect(find.byType(CommunityBanner), findsNothing);
    expect(find.byType(AnnouncementsCard), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a room that is only called Announcements is not one', (
    tester,
  ) async {
    addSpace();
    addGroup(_news, levels: {'events_default': 0}, last: 'hi');
    await harness.open(tester, path: path());
    expect(find.byType(AnnouncementsCard), findsNothing);
    await harness.finish(tester);
  });

  testWidgets(
    'the last message is left out when the retention timer hides it',
    (tester) async {
      addSpace();
      addGroup(
        _news,
        levels: announcementsLevelsFor(harness),
        last: 'Expired notice',
        at: DateTime.now().subtract(const Duration(days: 5)),
        retention: {
          'max_lifetime': const Duration(days: 1).inMilliseconds,
          'expire_on_clients': true,
        },
      );
      await harness.open(tester, path: path());
      expect(find.byType(AnnouncementsCard), findsOneWidget);
      expect(find.text('Expired notice'), findsNothing);
      await harness.finish(tester);
    },
  );

  testWidgets('the card opens the announcements room', (tester) async {
    addSpace();
    addGroup(_news, levels: announcementsLevelsFor(harness), last: 'Hi');
    await harness.open(tester, path: path());
    await tester.tap(find.byType(AnnouncementsCard));
    await harness.settle(tester, rounds: 3);
    expect(
      Uri.parse(
        FluffyChatApp.router.routeInformationProvider.value.uri.toString(),
      ).path,
      '/rooms/$_news',
    );
    await harness.finish(tester);
  });

  testWidgets('an alias that would add parameters is not put into the link', (
    tester,
  ) async {
    addSpace(alias: '#a?via=evil.example:example.org');
    addGroup(_news, levels: announcementsLevelsFor(harness));
    await harness.open(tester, path: path());
    await tester.tap(find.text(l10n(tester).communityInviteLink));
    await harness.settle(tester, rounds: 3);
    expect(clipboard, [
      'https://matrix.to/#/$_space?via=fakeServer.notExisting',
    ]);
    await harness.finish(tester);
  });

  testWidgets(
    'the invite link has the alias and only the own server, and nothing is sent',
    (tester) async {
      addSpace(alias: '#makers:example.org');
      addGroup(_news, levels: announcementsLevelsFor(harness));
      await harness.open(tester, path: path());
      api.clear();
      await tester.tap(find.text(l10n(tester).communityInviteLink));
      await harness.settle(tester, rounds: 3);
      expect(clipboard, [
        'https://matrix.to/#/#makers:example.org?via=fakeServer.notExisting',
      ]);
      expect(api.log.where((r) => r.method != 'GET'), isEmpty);
      await harness.finish(tester);
    },
  );

  testWidgets('without an alias the link uses the room id', (tester) async {
    addSpace();
    addGroup(_news, levels: announcementsLevelsFor(harness));
    await harness.open(tester, path: path());
    await tester.tap(find.text(l10n(tester).communityInviteLink));
    await harness.settle(tester, rounds: 3);
    expect(clipboard, [
      'https://matrix.to/#/$_space?via=fakeServer.notExisting',
    ]);
    await harness.finish(tester);
  });

  testWidgets('only admins can add an announcements room', (tester) async {
    addSpace();
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    await tester.tap(find.byType(PopupMenuButton<void>));
    await harness.settle(tester, rounds: 2);
    expect(find.text(l10n(tester).communityAddAnnouncements), findsNothing);
    await harness.finish(tester);
  });

  Finder rowOf(String id) => find.byKey(ValueKey('overview_$id'));

  testWidgets('an admin removes a room from the space after confirming', (
    tester,
  ) async {
    addSpace(admin: true);
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    await tester.longPress(rowOf(_general));
    await harness.settle(tester, rounds: 3);
    expect(find.text(l10n(tester).removeFromSpaceDescription), findsOneWidget);
    expect(api.requests('/state/m.space.child/', method: 'PUT'), isEmpty);
    await tester.tap(find.text(l10n(tester).ok));
    await harness.settle(tester, rounds: 4);
    final puts = api.requests('/state/m.space.child/', method: 'PUT');
    expect(puts, hasLength(1));
    expect(puts.single.path, contains(_space));
    expect(puts.single.path, endsWith('/$_general'));
    expect(puts.single.json, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('cancelling the removal changes nothing', (tester) async {
    addSpace(admin: true);
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    await tester.longPress(rowOf(_general));
    await harness.settle(tester, rounds: 3);
    await tester.tap(find.text(l10n(tester).cancel));
    await harness.settle(tester, rounds: 3);
    expect(api.requests('/state/m.space.child/', method: 'PUT'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a member cannot remove a room from the space', (tester) async {
    addSpace();
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    final description = l10n(tester).removeFromSpaceDescription;
    await tester.longPress(rowOf(_general));
    await harness.settle(tester, rounds: 3);
    expect(find.text(description), findsNothing);
    expect(api.requests('/state/m.space.child/', method: 'PUT'), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('an admin of a plain space is offered it, with the honest note', (
    tester,
  ) async {
    addSpace(admin: true);
    addGroup(_general, levels: {'events_default': 0});
    await harness.open(tester, path: path());
    await tester.tap(find.byType(PopupMenuButton<void>));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.text(l10n(tester).communityAddAnnouncements));
    await harness.settle(tester, rounds: 3);
    expect(find.text(l10n(tester).communityNoChannelsNote), findsOneWidget);
    await harness.finish(tester);
  });
  group('notifications of a community', () {
    const newsRule = '/client/v3/pushrules/global/room/!news%3Aexample.org';
    const newsOverride =
        '/client/v3/pushrules/global/override/!news%3Aexample.org';

    void joinCommunity() {
      addSpace();
      addGroup(_news, levels: announcementsLevelsFor(harness), last: 'Hi');
      addGroup(_general, levels: {'events_default': 0});
      for (final path in [newsRule, newsOverride]) {
        api.api['PUT']![path] = (_) => <String, Object?>{};
        api.api['DELETE']![path] = (_) => <String, Object?>{};
      }
    }

    void announcementsRule(String kind, {List<Object?>? conditions}) {
      harness.client.accountData['m.push_rules'] = BasicEvent(
        type: 'm.push_rules',
        content: {
          'global': {
            kind: [
              {
                'rule_id': _news,
                'default': false,
                'enabled': true,
                'actions': <Object?>[],
                'conditions': ?conditions,
              },
            ],
          },
        },
      );
    }

    Future<void> pick(WidgetTester tester, String option) async {
      await tester.tap(find.byType(SpaceActionButton).last);
      await harness.settle(tester, rounds: 3);
      await tester.tap(find.text(option));
      await harness.settle(tester, rounds: 3);
    }

    List<RecordedRequest> writes() => api.log
        .where((r) => r.method != 'GET' && r.path.contains('pushrules'))
        .toList();

    tearDown(() {
      harness.client.accountData.remove('m.push_rules');
      api.api['PUT']!.remove(newsRule);
      api.api['PUT']!.remove(newsOverride);
      api.api['DELETE']!.remove(newsRule);
      api.api['DELETE']!.remove(newsOverride);
    });

    testWidgets('three choices are offered and none touches the space', (
      tester,
    ) async {
      joinCommunity();
      await harness.open(tester, path: path());
      api.clear();
      await tester.tap(find.byType(SpaceActionButton).last);
      await harness.settle(tester, rounds: 3);
      final texts = l10n(tester);
      Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );
      expect(inSheet(texts.communityNotificationsAll), findsOneWidget);
      expect(inSheet(texts.communityNotificationsMentions), findsOneWidget);
      expect(inSheet(texts.muted), findsOneWidget);
      expect(inSheet(texts.communityNotificationsNote), findsOneWidget);
      expect(writes(), isEmpty);
      await harness.finish(tester);
    });

    testWidgets('mentions only sets the room rule of the announcements room', (
      tester,
    ) async {
      joinCommunity();
      await harness.open(tester, path: path());
      api.clear();
      await pick(tester, l10n(tester).communityNotificationsMentions);
      final sent = writes();
      expect(sent, hasLength(1));
      expect(sent.single.method, 'PUT');
      expect(sent.single.path, contains('/pushrules/global/room/$_news'));
      expect(sent.single.json, {'actions': <Object?>[]});
      expect(api.log.any((r) => r.path.contains(_space)), isFalse);
      await harness.finish(tester);
    });

    testWidgets('mute sets an override rule for the announcements room', (
      tester,
    ) async {
      joinCommunity();
      await harness.open(tester, path: path());
      api.clear();
      await pick(tester, l10n(tester).muted);
      final sent = writes();
      expect(sent, hasLength(1));
      expect(sent.single.path, contains('/pushrules/global/override/$_news'));
      final body = sent.single.json! as Map<String, Object?>;
      expect(body['actions'], isEmpty);
      expect(body['conditions'], [
        {'kind': 'event_match', 'key': 'room_id', 'pattern': _news},
      ]);
      expect(api.log.any((r) => r.path.contains(_space)), isFalse);
      await harness.finish(tester);
    });

    testWidgets('all messages removes the rule of the announcements room', (
      tester,
    ) async {
      joinCommunity();
      announcementsRule('room');
      await harness.open(tester, path: path());
      api.clear();
      await pick(tester, l10n(tester).communityNotificationsAll);
      final sent = writes();
      expect(sent, hasLength(1));
      expect(sent.single.method, 'DELETE');
      expect(sent.single.path, contains('/pushrules/global/room/$_news'));
      await harness.finish(tester);
    });

    testWidgets('the button says which choice is active, not only the icon', (
      tester,
    ) async {
      joinCommunity();
      announcementsRule('room');
      final handle = tester.ensureSemantics();
      await harness.open(tester, path: path());
      final texts = l10n(tester);
      expect(find.text(texts.communityNotificationsMentions), findsOneWidget);
      final semantics = tester.getSemantics(
        find.bySemanticsLabel(texts.notifications),
      );
      expect(semantics.label, texts.notifications);
      expect(semantics.value, texts.communityNotificationsMentions);
      handle.dispose();
      await harness.finish(tester);
    });

    testWidgets('the button shows the choice before the next sync', (
      tester,
    ) async {
      joinCommunity();
      await harness.open(tester, path: path());
      final texts = l10n(tester);
      expect(find.text(texts.communityNotificationsAll), findsOneWidget);
      await pick(tester, texts.communityNotificationsMentions);
      expect(find.text(texts.communityNotificationsMentions), findsOneWidget);
      expect(find.text(texts.communityNotificationsAll), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('a later sync with the push rules replaces the remembered '
        'choice', (tester) async {
      joinCommunity();
      await harness.open(tester, path: path());
      final texts = l10n(tester);
      await pick(tester, texts.communityNotificationsMentions);
      expect(find.text(texts.communityNotificationsMentions), findsOneWidget);
      final rules = BasicEvent(
        type: 'm.push_rules',
        content: {
          'global': {
            'override': [
              {
                'rule_id': _news,
                'default': false,
                'enabled': true,
                'actions': <Object?>[],
                'conditions': [
                  {'kind': 'event_match', 'key': 'room_id', 'pattern': _news},
                ],
              },
            ],
          },
        },
      );
      harness.client.accountData['m.push_rules'] = rules;
      harness.client.onSync.add(
        SyncUpdate(nextBatch: 's1', accountData: [rules]),
      );
      await harness.settle(tester, rounds: 3);
      expect(find.text(texts.muted), findsOneWidget);
      expect(find.text(texts.communityNotificationsMentions), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('a refused change leaves the button as it was', (tester) async {
      joinCommunity();
      api.onRequest = (request) async {
        if (request.method == 'PUT' && request.url.path.contains('pushrules')) {
          throw Exception('refused');
        }
      };
      await harness.open(tester, path: path());
      final texts = l10n(tester);
      await pick(tester, texts.communityNotificationsMentions);
      await harness.settle(tester, rounds: 3);
      expect(find.text(texts.close), findsOneWidget);
      await tester.tap(find.text(texts.close));
      await harness.settle(tester, rounds: 3);
      expect(find.text(texts.communityNotificationsAll), findsOneWidget);
      expect(find.text(texts.communityNotificationsMentions), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('the popup marks the active choice', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      joinCommunity();
      announcementsRule('room');
      await harness.open(tester, path: path());
      await tester.tap(find.byType(SpaceActionButton).last);
      await harness.settle(tester, rounds: 3);
      final actions = tester
          .widgetList<CupertinoActionSheetAction>(
            find.byType(CupertinoActionSheetAction),
          )
          .toList();
      expect(actions.take(3).map((a) => a.isDefaultAction), [
        false,
        true,
        false,
      ]);
      debugDefaultTargetPlatformOverride = null;
      await harness.finish(tester);
    });

    testWidgets('closing the choice without a pick sends nothing', (
      tester,
    ) async {
      joinCommunity();
      await harness.open(tester, path: path());
      api.clear();
      await tester.tap(find.byType(SpaceActionButton).last);
      await harness.settle(tester, rounds: 3);
      await tester.tapAt(const Offset(5, 5));
      await harness.settle(tester, rounds: 3);
      expect(writes(), isEmpty);
      await harness.finish(tester);
    });
  });
}

Map<String, Object?> announcementsLevelsFor(ChatPageHarness harness) => {
  'events_default': 100,
  'users_default': 0,
  'users': {harness.client.userID!: 0},
};
