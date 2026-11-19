// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat_list/folder_filter.dart';
import 'package:odango/utils/chat_list/folder_ref.dart';
import 'package:odango/utils/chat_list/folder_store.dart';
import 'package:odango/utils/chat_list/space_tabs_model.dart';
import 'package:odango/utils/chat_list/unread_counts.dart';
import 'package:odango/utils/matrix_sdk_extensions/chat_list_room_extension.dart';

import 'utils/space_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  tearDown(() => client.accountData.remove('m.direct'));

  Room room(
    String id, {
    int unread = 0,
    Membership? membership,
    List<String> tags = const [],
    Map<String, double?> ordered = const {},
  }) {
    final r = testSpaceChild(
      client,
      id,
      unread: unread,
      membership: membership,
    );
    if (tags.isNotEmpty || ordered.isNotEmpty) {
      r.roomAccountData['m.tag'] = BasicEvent(
        type: 'm.tag',
        content: {
          'tags': {
            for (final tag in tags) tag: <String, Object?>{},
            for (final e in ordered.entries)
              e.key: <String, Object?>{'order': ?e.value},
          },
        },
      );
    }
    return r;
  }

  void markDirect(List<String> ids) => client.accountData['m.direct'] =
      BasicEvent(type: 'm.direct', content: {'@friend:x': ids});

  SpaceTabsModel model(List<Room> rooms) =>
      SpaceTabsModel.build(rooms, nameOf: (r) => r.id);

  List<String> ids(List<Room> rooms) => rooms.map((r) => r.id).toList();

  group('FolderRef.parse', () {
    test('stored values keep working', () {
      expect(FolderRef.parse('allChats'), FolderRef.all);
      expect(FolderRef.parse('unread'), FolderRef.unread);
      expect(FolderRef.parse('messages'), FolderRef.personal);
      expect(FolderRef.parse('groups'), FolderRef.groups);
      expect(
        FolderRef.parse('u.work'),
        const FolderRef(FolderKind.tag, 'u.work'),
      );
      expect(
        FolderRef.parse('folder:k3x9a2b7'),
        const FolderRef(FolderKind.user, 'k3x9a2b7'),
      );
    });

    test('bad values fall back to all', () {
      expect(FolderRef.parse(null), FolderRef.all);
      expect(FolderRef.parse(''), FolderRef.all);
      expect(FolderRef.parse('garbage'), FolderRef.all);
      expect(FolderRef.parse('folder:BAD!'), FolderRef.all);
      expect(FolderRef.parse('folder:'), FolderRef.all);
      expect(FolderRef.parse('u.${'a' * 300}'), FolderRef.all);
      expect(FolderRef.parse('bots'), FolderRef.all);
    });

    test('storageKey round-trips', () {
      for (final ref in [
        FolderRef.all,
        FolderRef.unread,
        FolderRef.personal,
        FolderRef.groups,
        const FolderRef(FolderKind.tag, 'u.work'),
        const FolderRef(FolderKind.user, 'k3x9a2b7'),
      ]) {
        expect(FolderRef.parse(ref.storageKey), ref);
      }
    });

    test('SpaceNavigationMode treats anything but switcher as tabs', () {
      expect(
        SpaceNavigationMode.fromSetting('switcher'),
        SpaceNavigationMode.switcher,
      );
      expect(SpaceNavigationMode.fromSetting('tabs'), SpaceNavigationMode.tabs);
      expect(SpaceNavigationMode.fromSetting('x'), SpaceNavigationMode.tabs);
      expect(SpaceNavigationMode.fromSetting(''), SpaceNavigationMode.tabs);
    });
  });

  group('FolderFilter.apply', () {
    test('a joined space is dropped, an invited space is kept', () {
      final rooms = [
        testSpace(client, [], id: '!joined:x'),
        testSpace(client, [], id: '!invited:x', membership: Membership.invite),
        room('!r:x'),
      ];
      final result = FolderFilter.apply(
        rooms,
        const ChatListScope(),
        FolderContext(spaces: model(rooms)),
      );
      expect(ids(result), ['!invited:x', '!r:x']);
    });

    test('a space scope keeps only descendants', () {
      final rooms = [
        testSpace(client, ['!a:x', '!b:x'], id: '!s:x'),
        room('!a:x'),
        room('!b:x'),
        room('!c:x'),
      ];
      final result = FolderFilter.apply(
        rooms,
        const ChatListScope(spaceId: '!s:x'),
        FolderContext(spaces: model(rooms)),
      );
      expect(ids(result), ['!a:x', '!b:x']);
    });

    test('an unknown space id shows nothing', () {
      final rooms = [room('!a:x')];
      expect(
        FolderFilter.apply(
          rooms,
          const ChatListScope(spaceId: '!gone:x'),
          FolderContext(spaces: model(rooms)),
        ),
        isEmpty,
      );
    });

    test('hideRoomsInSpaces hides only in All without a space', () {
      final rooms = [
        testSpace(client, ['!a:x'], id: '!s:x'),
        room('!a:x'),
        room('!b:x'),
      ];
      final ctx = FolderContext(spaces: model(rooms), hideRoomsInSpaces: true);
      expect(ids(FolderFilter.apply(rooms, const ChatListScope(), ctx)), [
        '!b:x',
      ]);
      expect(
        ids(
          FolderFilter.apply(
            rooms,
            const ChatListScope(folder: FolderRef.groups),
            ctx,
          ),
        ),
        ['!a:x', '!b:x'],
      );
      expect(
        ids(
          FolderFilter.apply(rooms, const ChatListScope(spaceId: '!s:x'), ctx),
        ),
        ['!a:x'],
      );
    });

    test('unread, personal, groups and tag folders', () {
      final rooms = [
        room('!dm:x', unread: 1),
        room('!g1:x'),
        room('!g2:x', unread: 2, tags: ['u.work']),
        room('!inv:x', membership: Membership.invite),
      ];
      markDirect(['!dm:x']);
      final ctx = FolderContext(spaces: model(rooms));
      List<String> run(FolderRef f) =>
          ids(FolderFilter.apply(rooms, ChatListScope(folder: f), ctx));
      expect(run(FolderRef.unread), ['!dm:x', '!g2:x', '!inv:x']);
      expect(run(FolderRef.personal), ['!dm:x']);
      expect(run(FolderRef.groups), ['!g1:x', '!g2:x', '!inv:x']);
      expect(run(const FolderRef(FolderKind.tag, 'u.work')), ['!g2:x']);
      expect(run(const FolderRef(FolderKind.user, 'nope')), isEmpty);
    });

    test('input order is preserved', () {
      final rooms = [room('!z:x'), room('!a:x'), room('!m:x')];
      expect(
        ids(
          FolderFilter.apply(
            rooms,
            const ChatListScope(),
            FolderContext(spaces: model(rooms)),
          ),
        ),
        ['!z:x', '!a:x', '!m:x'],
      );
    });
  });

  test('built-in tabs are unread, personal, groups (no Bots)', () {
    expect(FolderFilter.builtInTabs, [
      FolderRef.unread,
      FolderRef.personal,
      FolderRef.groups,
    ]);
  });

  test('unreadCount equals apply(...).where(unread) on 200 rooms', () {
    final rooms = [
      for (var i = 0; i < 200; i++) room('!r$i:x', unread: i % 4 == 0 ? 1 : 0),
      testSpace(client, ['!r1:x', '!r4:x', '!r8:x'], id: '!s:x'),
    ];
    markDirect([for (var i = 0; i < 200; i += 3) '!r$i:x']);
    final ctx = FolderContext(spaces: model(rooms), hideRoomsInSpaces: true);
    final unreadRooms = rooms.where((r) => r.isUnreadOrInvited);
    for (final scope in [
      const ChatListScope(),
      const ChatListScope(spaceId: '!s:x'),
      const ChatListScope(folder: FolderRef.personal),
      const ChatListScope(folder: FolderRef.groups),
      const ChatListScope(folder: FolderRef.unread),
    ]) {
      expect(
        FolderFilter.unreadCount(unreadRooms, scope, ctx),
        FolderFilter.apply(
          rooms,
          scope,
          ctx,
        ).where((r) => r.isUnreadOrInvited).length,
      );
    }
  });

  test('unreadChatCount ignores joined spaces and read rooms', () {
    final rooms = [
      room('!a:x', unread: 3),
      room('!b:x'),
      room('!c:x', membership: Membership.invite),
      testSpace(client, [], id: '!s:x')..notificationCount = 4,
    ];
    expect(unreadChatCount(rooms), 2);
  });

  group('tab list', () {
    const spaceA = SpaceTab(
      spaceId: '!a:x',
      name: 'A',
      avatar: null,
      unread: 0,
    );
    const spaceB = SpaceTab(
      spaceId: '!b:x',
      name: 'B',
      avatar: null,
      unread: 0,
    );
    List<String> labels(List<ChatListTabItem> tabs) =>
        tabs.map((t) => t.space?.name ?? t.folder.storageKey).toList();

    test('tabs mode: all, spaces, then folders', () {
      final tabs = FolderFilter.tabs(
        mode: SpaceNavigationMode.tabs,
        spaces: [spaceA, spaceB],
        tags: ['u.work'],
        showFoldersAfterSpaces: true,
      );
      expect(labels(tabs), [
        'allChats',
        'A',
        'B',
        'unread',
        'messages',
        'groups',
        'u.work',
      ]);
      expect(tabs[1].scope.spaceId, '!a:x');
      expect(tabs[3].scope.spaceId, isNull);
    });

    test('tabs mode: setting off hides folders when there are spaces', () {
      final tabs = FolderFilter.tabs(
        mode: SpaceNavigationMode.tabs,
        spaces: [spaceA, spaceB],
        tags: [],
        showFoldersAfterSpaces: false,
      );
      expect(labels(tabs), ['allChats', 'A', 'B']);
    });

    test('tabs mode: no spaces still shows the folders', () {
      final tabs = FolderFilter.tabs(
        mode: SpaceNavigationMode.tabs,
        spaces: [],
        tags: [],
        showFoldersAfterSpaces: false,
      );
      expect(labels(tabs), ['allChats', 'unread', 'messages', 'groups']);
    });

    test('switcher mode: folders only, carrying the chosen space', () {
      final tabs = FolderFilter.tabs(
        mode: SpaceNavigationMode.switcher,
        spaces: [spaceA],
        tags: [],
        showFoldersAfterSpaces: false,
        currentSpaceId: '!a:x',
      );
      expect(labels(tabs), ['allChats', 'unread', 'messages', 'groups']);
      expect(tabs.every((t) => t.scope.spaceId == '!a:x'), isTrue);
    });
  });

  group('W03-2: user folders', () {
    List<String> run(
      List<Room> rooms,
      UserFolder folder, {
      bool archived = false,
    }) => ids(
      FolderFilter.apply(
        rooms,
        ChatListScope(
          folder: FolderRef(FolderKind.user, folder.id),
          archived: archived,
        ),
        FolderContext(spaces: model(rooms), userFolders: [folder]),
      ),
    );

    test('a folder matches listed rooms', () {
      final rooms = [room('!a:x'), room('!b:x'), room('!c:x')];
      expect(
        run(rooms, UserFolder(id: 'f', name: 'F', rooms: ['!c:x', '!a:x'])),
        ['!a:x', '!c:x'],
      );
    });

    test('a folder matches chat types', () {
      final rooms = [room('!dm:x'), room('!g:x')];
      markDirect(['!dm:x']);
      expect(
        run(rooms, UserFolder(id: 'f', name: 'F', types: {FolderChatType.dm})),
        ['!dm:x'],
      );
      expect(
        run(
          rooms,
          UserFolder(id: 'f', name: 'F', types: {FolderChatType.group}),
        ),
        ['!g:x'],
      );
    });

    test('a folder without types and rooms shows nothing', () {
      expect(run([room('!a:x')], UserFolder(id: 'f', name: 'F')), isEmpty);
    });

    test('exclude muted and exclude read', () {
      client.accountData['m.push_rules'] = BasicEvent(
        type: 'm.push_rules',
        content: {
          'global': {
            'override': [
              {
                'rule_id': '!muted:x',
                'default': false,
                'enabled': true,
                'conditions': <Object?>[],
                'actions': <Object?>[],
              },
            ],
          },
        },
      );
      addTearDown(() => client.accountData.remove('m.push_rules'));
      final rooms = [
        room('!muted:x', unread: 1),
        room('!unread:x', unread: 2),
        room('!read:x'),
      ];
      expect(rooms.first.pushRuleState, PushRuleState.dontNotify);
      final all = UserFolder(
        id: 'f',
        name: 'F',
        rooms: ['!muted:x', '!unread:x', '!read:x'],
      );
      expect(run(rooms, all), ['!muted:x', '!unread:x', '!read:x']);
      expect(run(rooms, all.copyWith(excludeMuted: true)), [
        '!unread:x',
        '!read:x',
      ]);
      expect(run(rooms, all.copyWith(excludeRead: true)), [
        '!muted:x',
        '!unread:x',
      ]);
    });

    test('a missing folder id shows nothing', () {
      final rooms = [room('!a:x')];
      expect(
        FolderFilter.apply(
          rooms,
          const ChatListScope(folder: FolderRef(FolderKind.user, 'gone')),
          FolderContext(spaces: model(rooms)),
        ),
        isEmpty,
      );
    });

    test('user folders become tabs between the built-ins and the tags', () {
      final tabs = FolderFilter.tabs(
        mode: SpaceNavigationMode.tabs,
        spaces: [],
        tags: ['u.work'],
        userFolders: [UserFolder(id: 'k1', name: 'Family')],
        showFoldersAfterSpaces: true,
      );
      expect(tabs.map((t) => t.label ?? t.folder.storageKey).toList(), [
        'allChats',
        'unread',
        'messages',
        'groups',
        'Family',
        'u.work',
      ]);
      expect(tabs[4].folder, const FolderRef(FolderKind.user, 'k1'));
    });
  });

  group('W03-2: archive', () {
    test('an archived room only shows in the archived scope', () {
      final rooms = [
        room('!a:x', tags: [archivedTag]),
        room('!b:x'),
      ];
      final ctx = FolderContext(spaces: model(rooms));
      expect(ids(FolderFilter.apply(rooms, const ChatListScope(), ctx)), [
        '!b:x',
      ]);
      expect(
        ids(
          FolderFilter.apply(rooms, const ChatListScope(archived: true), ctx),
        ),
        ['!a:x'],
      );
    });

    test('archived rooms are not in unread counts or the chats badge', () {
      final rooms = [
        room('!a:x', unread: 3, tags: [archivedTag]),
        room('!b:x', unread: 1),
      ];
      final ctx = FolderContext(spaces: model(rooms));
      expect(
        FolderFilter.unreadCount(
          rooms.where((r) => r.isUnreadOrInvited),
          const ChatListScope(),
          ctx,
        ),
        1,
      );
      expect(unreadChatCount(rooms), 1);
    });

    test('the archived scope respects the current space', () {
      final rooms = [
        testSpace(client, ['!in:x'], id: '!s:x'),
        room('!in:x', tags: [archivedTag]),
        room('!out:x', tags: [archivedTag]),
      ];
      expect(
        ids(
          FolderFilter.apply(
            rooms,
            const ChatListScope(spaceId: '!s:x', archived: true),
            FolderContext(spaces: model(rooms)),
          ),
        ),
        ['!in:x'],
      );
    });

    test('an invite that kept the archived tag is not archived (L1)', () {
      final invite = room(
        '!i:x',
        membership: Membership.invite,
        tags: [archivedTag],
      );
      final rooms = [invite, room('!b:x')];
      final ctx = FolderContext(spaces: model(rooms));
      expect(invite.isArchivedChat, isFalse);
      expect(ids(FolderFilter.apply(rooms, const ChatListScope(), ctx)), [
        '!i:x',
        '!b:x',
      ]);
      expect(
        FolderFilter.apply(rooms, const ChatListScope(archived: true), ctx),
        isEmpty,
      );
      expect(unreadChatCount(rooms), 1);
      expect(
        room(
          '!l:x',
          membership: Membership.leave,
          tags: [archivedTag],
        ).isArchivedChat,
        isFalse,
      );
    });

    test('isArchivedChat reads only the custom tag', () {
      expect(room('!a:x', tags: [archivedTag]).isArchivedChat, isTrue);
      expect(room('!a:x', tags: ['m.lowpriority']).isArchivedChat, isFalse);
      expect(room('!a:x').isArchivedChat, isFalse);
    });

    test('scope equality includes archived', () {
      expect(const ChatListScope(), isNot(const ChatListScope(archived: true)));
      expect(
        const ChatListScope().copyWith(archived: true),
        const ChatListScope(archived: true),
      );
    });
  });

  group('W03-2: pin order', () {
    List<String> run(List<Room> rooms) => ids(
      FolderFilter.apply(
        rooms,
        const ChatListScope(),
        FolderContext(spaces: model(rooms)),
      ),
    );

    test('favourites sort by order, hostile orders count as unset', () {
      final rooms = [
        room('!nan:x', ordered: {'m.favourite': double.nan}),
        room('!late:x', ordered: {'m.favourite': 0.9}),
        room('!none:x', tags: ['m.favourite']),
        room('!early:x', ordered: {'m.favourite': 0.1}),
        room('!inf:x', ordered: {'m.favourite': double.infinity}),
        room('!neg:x', ordered: {'m.favourite': -1.0}),
        room('!plain:x'),
      ];
      expect(run(rooms), [
        '!early:x',
        '!late:x',
        '!nan:x',
        '!none:x',
        '!inf:x',
        '!neg:x',
        '!plain:x',
      ]);
    });

    test('non favourites keep their order', () {
      final rooms = [
        room('!z:x'),
        room('!pin:x', ordered: {'m.favourite': 0.5}),
        room('!a:x'),
      ];
      expect(run(rooms), ['!z:x', '!pin:x', '!a:x']);
    });

    test('pinOrder validates the range', () {
      expect(room('!a:x', ordered: {'m.favourite': 0.25}).pinOrder, 0.25);
      expect(room('!a:x', ordered: {'m.favourite': 1.5}).pinOrder, isNull);
      expect(room('!a:x', tags: ['m.favourite']).pinOrder, isNull);
      expect(room('!a:x').pinOrder, isNull);
    });

    test('pinOrderForNew puts a new pin on top', () {
      expect(pinOrderForNew([]), 0.5);
      expect(pinOrderForNew([0.4, 0.2]), 0.1);
      expect(pinOrderForNew([double.infinity, -1, null]), 0.5);
      expect(pinOrderForNew([1e-10]), 0.0);
      expect(pinOrderForNew([0.5, null]), 0.25);
    });
  });
}
