// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/spaces/community_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = '@me:example.org';

ChildPowerLevels child(
  Map<String, Object?>? levels, {
  String id = '!a:example.org',
  bool joined = true,
  bool isSpace = false,
}) => ChildPowerLevels(
  roomId: id,
  joined: joined,
  isSpace: isSpace,
  powerLevels: levels,
);

AnnouncementsRoom? find(List<ChildPowerLevels> children) =>
    CommunityModel.find(children, ownUserId: _me);

void main() {
  group('posting level', () {
    test('events_default decides', () {
      expect(CommunityModel.postingLevel({'events_default': 50}), 50);
      expect(CommunityModel.postingLevel({'events_default': 100}), 100);
      expect(CommunityModel.postingLevel({}), 0);
      expect(CommunityModel.postingLevel(null), 0);
    });

    test('an override for messages wins over events_default', () {
      expect(
        CommunityModel.postingLevel({
          'events_default': 100,
          'events': {'m.room.message': 0},
        }),
        0,
      );
      expect(
        CommunityModel.postingLevel({
          'events_default': 0,
          'events': {'m.room.message': 75},
        }),
        75,
      );
    });

    test('values that are not integers count as zero', () {
      for (final value in <Object?>[
        '50',
        50.5,
        null,
        true,
        [50],
        {'a': 50},
      ]) {
        expect(
          CommunityModel.postingLevel({'events_default': value}),
          0,
          reason: '$value',
        );
      }
      expect(
        CommunityModel.postingLevel({'events': 'x', 'events_default': 50}),
        50,
      );
      expect(
        CommunityModel.postingLevel({
          'events': {'m.room.message': '0'},
          'events_default': 50,
        }),
        50,
      );
    });
  });

  group('find', () {
    test('level 50 and 100 qualify, 49 does not', () {
      expect(
        find([
          child({'events_default': 50}),
        ])?.postingLevel,
        50,
      );
      expect(
        find([
          child({'events_default': 100}),
        ])?.postingLevel,
        100,
      );
      expect(
        find([
          child({'events_default': 49}),
        ]),
        isNull,
      );
      expect(
        find([
          child({'events_default': 0}),
        ]),
        isNull,
      );
    });

    test('an override that lets everyone post disqualifies', () {
      expect(
        find([
          child({
            'events_default': 100,
            'events': {'m.room.message': 0},
          }),
        ]),
        isNull,
      );
    });

    test('ordinary members must not be able to post', () {
      expect(
        find([
          child({'events_default': 50, 'users_default': 50}),
        ]),
        isNull,
      );
      expect(
        find([
          child({'events_default': 50, 'users_default': 10}),
        ]),
        isNotNull,
      );
    });

    test('rooms that were not joined or have no power levels are ignored', () {
      expect(
        find([
          child({'events_default': 100}, joined: false),
        ]),
        isNull,
      );
      expect(find([child(null)]), isNull);
    });

    test('a subspace is never an announcements room', () {
      expect(
        find([
          child({'events_default': 100}, isSpace: true),
        ]),
        isNull,
      );
    });

    test('the first match in hierarchy order wins', () {
      final found = find([
        child({'events_default': 0}, id: '!open:example.org'),
        child({'events_default': 100}, id: '!news:example.org'),
        child({'events_default': 50}, id: '!other:example.org'),
      ]);
      expect(found?.roomId, '!news:example.org');
    });

    test('a room that is only called Announcements is not one', () {
      expect(
        find([
          child({'events_default': 0}, id: '!announcements:example.org'),
        ]),
        isNull,
      );
    });

    test('userCanPost follows the own level', () {
      bool canPost(Map<String, Object?> users) => find([
        child({'events_default': 50, 'users': users}),
      ])!.userCanPost;
      expect(canPost({_me: 100}), isTrue);
      expect(canPost({_me: 50}), isTrue);
      expect(canPost({_me: 49}), isFalse);
      expect(canPost({}), isFalse);
      expect(canPost({'@other:example.org': 100}), isFalse);
    });

    test('hostile levels never throw', () {
      for (final levels in <Map<String, Object?>>[
        {'events_default': 50, 'users': 'x'},
        {
          'events_default': 50,
          'users': [1],
        },
        {'events_default': 50, 'users_default': 'x'},
        {
          'events_default': 50,
          'users': {_me: 'admin'},
        },
        {'events': 5},
      ]) {
        find([child(levels)]);
      }
    });
  });
}
