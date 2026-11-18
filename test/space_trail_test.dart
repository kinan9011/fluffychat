// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/spaces/space_trail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a space on the trail cannot be entered again', () {
    final trail = const SpaceTrail().enter('!a:example.org');
    expect(trail.canEnter('!a:example.org'), isFalse);
    expect(trail.canEnter('!b:example.org'), isTrue);
  });

  test(
    'an id with a comma can never be on the trail, so it is never entered',
    () {
      const hostile = ['!a,b:evil.example', '!c,d:evil.example'];
      for (final id in hostile) {
        expect(SpaceTrail.isSpaceId(id), isFalse);
        expect(const SpaceTrail().canEnter(id), isFalse);
      }
      expect(SpaceTrail.isSpaceId('!ok:example.org'), isTrue);
      expect(SpaceTrail.isSpaceId('!${'a' * 43}'), isTrue);
    },
  );

  test('the trail is limited to 8 spaces', () {
    var trail = const SpaceTrail();
    for (var n = 0; n < SpaceTrail.maxDepth; n++) {
      expect(trail.canEnter('!s$n:example.org'), isTrue);
      trail = trail.enter('!s$n:example.org');
    }
    expect(trail.canEnter('!next:example.org'), isFalse);
  });

  test('encode and parse round trip', () {
    final trail = const SpaceTrail()
        .enter('!a:example.org')
        .enter('!b:example.org');
    expect(SpaceTrail.parse(trail.encode()).ids, trail.ids);
    expect(const SpaceTrail().encode(), isNull);
  });

  group('parse of a hostile query', () {
    test('nothing', () {
      expect(SpaceTrail.parse(null).ids, isEmpty);
      expect(SpaceTrail.parse('').ids, isEmpty);
    });

    test('separators only', () {
      expect(SpaceTrail.parse(',,,').ids, isEmpty);
    });

    test('invalid ids are dropped', () {
      expect(
        SpaceTrail.parse(
          '!a:example.org,javascript:alert(1),#x:y,!b:example.org',
        ).ids,
        ['!a:example.org', '!b:example.org'],
      );
    });

    test('repeats are dropped', () {
      expect(SpaceTrail.parse('!a:example.org,!a:example.org').ids, [
        '!a:example.org',
      ]);
    });

    test('a hundred ids are cut at 8', () {
      final query = [
        for (var n = 0; n < 100; n++) '!s$n:example.org',
      ].join(',');
      expect(SpaceTrail.parse(query).ids.length, SpaceTrail.maxDepth);
    });

    test('a megabyte of junk does not blow up', () {
      expect(SpaceTrail.parse('x,' * 500000).ids, isEmpty);
    });
  });
}
