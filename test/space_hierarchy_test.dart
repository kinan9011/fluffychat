// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/spaces/space_hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;

const _root = '!root:example.org';

Map<String, Object?> room(
  Object? id, {
  Object? name = 'Room',
  Object? type,
  Object? members = 3,
  Object? topic,
  Object? alias,
  Object? avatar,
  Object? joinRule,
  Object? state,
}) => {
  'room_id': id,
  'name': name,
  'room_type': type,
  'num_joined_members': members,
  'topic': topic,
  'canonical_alias': alias,
  'avatar_url': avatar,
  'join_rule': joinRule,
  'children_state': state ?? <Object?>[],
};

Map<String, Object?> page(List<Object?> rooms, {Object? next}) => {
  'rooms': rooms,
  'next_batch': ?next,
};

HierarchyPage parse(Object? json, {Set<String> seen = const {}}) =>
    HierarchyParser.parse(json, rootId: _root, seen: seen);

void main() {
  group('a plain page', () {
    test('rooms and subspaces with their fields', () {
      final result = parse(
        page([
          room(_root, name: 'The space', type: 'm.space'),
          room(
            '!a:example.org',
            name: 'General',
            members: 12,
            topic: 'Say hi',
            alias: '#general:example.org',
            avatar: 'mxc://example.org/abc',
            joinRule: 'public',
          ),
          room('!b:example.org', name: 'Sub', type: 'm.space', state: [{}, {}]),
        ], next: 'tok'),
      );
      expect(result.children.map((c) => c.roomId), [
        '!a:example.org',
        '!b:example.org',
      ]);
      final general = result.children.first;
      expect(general.name, 'General');
      expect(general.topic, 'Say hi');
      expect(general.alias, '#general:example.org');
      expect(general.avatar, Uri.parse('mxc://example.org/abc'));
      expect(general.memberCount, 12);
      expect(general.joinRule, 'public');
      expect(general.isSpace, isFalse);
      expect(result.children.last.isSpace, isTrue);
      expect(result.children.last.childCount, 2);
      expect(result.nextBatch, 'tok');
    });

    test('the root itself is not listed', () {
      expect(parse(page([room(_root)])).children, isEmpty);
    });

    test('version 12 room ids (no server part) are accepted', () {
      final id = '!${'a' * 43}';
      expect(parse(page([room(id)])).children.single.roomId, id);
    });
  });

  group('hostile payloads', () {
    test('not a map, no rooms, rooms of the wrong type', () {
      for (final json in <Object?>[
        null,
        'x',
        5,
        [1],
        <String, Object?>{},
        {'rooms': 'x'},
        {
          'rooms': {'a': 1},
        },
      ]) {
        final result = parse(json);
        expect(result.children, isEmpty, reason: '$json');
        expect(result.nextBatch, isNull);
      }
    });

    test('a page of 100000 rooms is cut at 200, the rest is counted', () {
      final result = parse(
        page([for (var n = 0; n < 100000; n++) room('!r$n:example.org')]),
      );
      expect(result.children.length, HierarchyParser.maxEntriesPerPage);
      expect(result.dropped, 100000 - HierarchyParser.maxEntriesPerPage);
    });

    test('malformed ids are dropped', () {
      final result = parse(
        page([
          room(null),
          room(5),
          room(''),
          room('!x'),
          room('x:example.org'),
          room('#alias:example.org'),
          room(r'$event:example.org'),
          room('!${'a' * 10000}:example.org'),
          room('!with space:example.org'),
          room('!a,b:evil.example'),
          room('!ok:example.org'),
        ]),
      );
      expect(result.children.map((c) => c.roomId), ['!ok:example.org']);
    });

    test(
      'duplicates keep the first, ids that were shown before are skipped',
      () {
        final result = parse(
          page([
            room('!a:example.org', name: 'First'),
            room('!a:example.org', name: 'Second'),
            room('!b:example.org'),
          ]),
          seen: {'!b:example.org'},
        );
        expect(result.children.map((c) => c.name), ['First']);
      },
    );

    test('entries that are not maps are dropped, the page survives', () {
      final result = parse(
        page([null, 5, 'x', <Object?>[], room('!ok:example.org')]),
      );
      expect(result.children.length, 1);
    });

    test('a page with only malformed entries is an empty page', () {
      final result = parse(page([for (var n = 0; n < 50; n++) 'x$n']));
      expect(result.children, isEmpty);
    });

    test('room types other than space are hidden', () {
      final result = parse(
        page([
          room('!a:example.org', type: 'm.call'),
          room('!b:example.org', type: 5),
          room('!c:example.org', type: <Object?>[]),
          room('!d:example.org', type: 'm.space'),
          room('!e:example.org'),
        ]),
      );
      expect(result.children.map((c) => c.roomId), [
        '!d:example.org',
        '!e:example.org',
      ]);
    });

    test('names: bidi, control, zero width, newlines, and 1 MB', () {
      final result = parse(
        page([
          room('!a:example.org', name: 'a\u202Eb\u200Bc\u0000d\ne'),
          room('!b:example.org', name: 'x' * 1000000),
          room('!c:example.org', name: null),
          room('!d:example.org', name: 5),
          room('!e:example.org', name: '   '),
        ]),
      );
      final names = result.children.map((c) => c.name).toList();
      expect(names[0], isNot(contains('\u202E')));
      expect(names[0], isNot(contains('\u200B')));
      expect(names[0], isNot(contains('\u0000')));
      expect(names[0], isNot(contains('\n')));
      expect(names[1]!.characters.length, HierarchyParser.maxNameChars);
      expect(names.sublist(2), [null, null, null]);
    });

    test('topics are cleaned and cut', () {
      final result = parse(
        page([
          room('!a:example.org', topic: 'y' * 1000000),
          room('!b:example.org', topic: 'a\u202Eb'),
        ]),
      );
      expect(
        result.children.first.topic!.characters.length,
        HierarchyParser.maxTopicChars,
      );
      expect(result.children.last.topic, isNot(contains('\u202E')));
    });

    test('avatars: only mxc uris with a server and an id', () {
      Uri? avatarOf(Object? value) => parse(
        page([room('!a:example.org', avatar: value)]),
      ).children.single.avatar;
      expect(avatarOf('mxc://example.org/abc'), isNotNull);
      for (final bad in <Object?>[
        'javascript:alert(1)',
        'http://example.org/x.png',
        'https://example.org/x.png',
        'file:///etc/passwd',
        'data:image/png;base64,AAAA',
        'mxc://',
        'mxc://example.org',
        'mxc://example.org/',
        'mxc://example.org/abc?x=1',
        'mxc://example.org/abc#f',
        'mxc://${'a' * 300}/abc',
        5,
        <Object?>[],
        '',
      ]) {
        expect(avatarOf(bad), isNull, reason: '$bad');
      }
    });

    test(
      'aliases: only #local:server without spaces or control characters',
      () {
        String? aliasOf(Object? value) => parse(
          page([room('!a:example.org', alias: value)]),
        ).children.single.alias;
        expect(aliasOf('#ok:example.org'), '#ok:example.org');
        for (final bad in <Object?>[
          'ok:example.org',
          '#no server',
          '#a b:example.org',
          '#a\u202Eb:example.org',
          '#${'a' * 300}:example.org',
          5,
          '',
        ]) {
          expect(aliasOf(bad), isNull, reason: '$bad');
        }
      },
    );

    test('member counts are clamped, odd types are zero', () {
      int membersOf(Object? value) => parse(
        page([room('!a:example.org', members: value)]),
      ).children.single.memberCount;
      expect(membersOf(7), 7);
      expect(membersOf(-1), 0);
      expect(membersOf(9223372036854775807), HierarchyParser.maxMembers);
      expect(membersOf(1e99), 0);
      expect(membersOf(12.5), 0);
      expect(membersOf('12'), 0);
      expect(membersOf(null), 0);
      expect(membersOf(true), 0);
    });

    test('join rules: only the known ones', () {
      String? ruleOf(Object? value) => parse(
        page([room('!a:example.org', joinRule: value)]),
      ).children.single.joinRule;
      expect(ruleOf('public'), 'public');
      expect(ruleOf('knock_restricted'), 'knock_restricted');
      expect(ruleOf('evil'), isNull);
      expect(ruleOf(5), isNull);
    });

    test('children_state with a million entries is not walked', () {
      final stopwatch = Stopwatch()..start();
      final result = parse(
        page([
          room('!a:example.org', state: List<Object?>.filled(1000000, 'x')),
        ]),
      );
      stopwatch.stop();
      expect(result.children.single.childCount, HierarchyParser.maxChildCount);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('children_state of the wrong type is zero', () {
      for (final state in <Object?>[
        'x',
        5,
        {'a': 1},
      ]) {
        final result = parse(page([room('!a:example.org', state: state)]));
        expect(result.children.single.childCount, 0);
      }
    });

    test('the next batch token: empty, huge or wrong typed ends paging', () {
      expect(parse(page([], next: 'x' * 512)).nextBatch, 'x' * 512);
      expect(parse(page([], next: 'x' * 513)).nextBatch, isNull);
      expect(parse(page([], next: 'x' * 1000000)).nextBatch, isNull);
      expect(parse(page([], next: '')).nextBatch, isNull);
      expect(parse(page([], next: 5)).nextBatch, isNull);
    });
  });

  group('HierarchyAccumulator', () {
    HierarchyPage pageOf(int from, int count, {String? next}) => HierarchyPage([
      for (var n = from; n < from + count; n++)
        HierarchyChild(
          roomId: '!r$n:example.org',
          name: 'r$n',
          topic: null,
          alias: null,
          avatar: null,
          isSpace: false,
          memberCount: 1,
          joinRule: null,
          childCount: 0,
        ),
    ], next);

    test('stops after ten pages', () {
      final acc = HierarchyAccumulator();
      for (var i = 0; i < HierarchyParser.maxPages; i++) {
        expect(acc.exhausted, isFalse);
        acc.add(pageOf(i * 10, 10, next: 'more'));
      }
      expect(acc.exhausted, isTrue);
    });

    test('stops at 500 entries and says it was capped', () {
      final acc = HierarchyAccumulator();
      for (var i = 0; i < 4; i++) {
        acc.add(pageOf(i * 200, 200, next: 'more'));
        if (acc.exhausted) break;
      }
      expect(acc.children.length, HierarchyParser.maxTotalEntries);
      expect(acc.capped, isTrue);
      expect(acc.exhausted, isTrue);
    });

    test('exactly 500 entries without a next page is not capped', () {
      final acc = HierarchyAccumulator();
      acc.add(pageOf(0, 200));
      acc.add(pageOf(200, 200));
      acc.add(pageOf(400, 100));
      expect(acc.children.length, 500);
      expect(acc.capped, isFalse);
    });

    test('an entry that was shown is not added again', () {
      final acc = HierarchyAccumulator();
      acc.add(pageOf(0, 5));
      final added = acc.add(pageOf(3, 5));
      expect(added.length, 3);
      expect(acc.children.length, 8);
    });
  });
}
