// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  final now = DateTime.utc(2031, 6, 1, 12);
  const day = Duration(days: 1);

  setUpAll(() async {
    client = await prepareTestClient();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  Map<String, Object?> content(Object? lifetime, {Object? expire = true}) => {
    'max_lifetime': lifetime,
    'expire_on_clients': ?expire,
  };

  Event event(
    DateTime at, {
    String type = EventTypes.Message,
    EventStatus status = EventStatus.synced,
    String id = r'$a:example.org',
  }) => Event(
    type: type,
    content: {'msgtype': 'm.text', 'body': 'hi'},
    room: room,
    eventId: id,
    senderId: '@bob:example.org',
    originServerTs: at,
    status: status,
  );

  group('fromContent', () {
    test('a valid one day timer', () {
      final policy = RetentionPolicy.fromContent(content(86400000))!;
      expect(policy.maxLifetime, day);
    });

    test('the one hour floor', () {
      expect(RetentionPolicy.fromContent(content(3599999)), isNull);
      expect(RetentionPolicy.fromContent(content(3600000)), isNotNull);
      expect(RetentionPolicy.fromContent(content(1000)), isNull);
      expect(RetentionPolicy.fromContent(content(0)), isNull);
      expect(RetentionPolicy.fromContent(content(-5)), isNull);
    });

    test('the five year ceiling', () {
      final ceiling = const Duration(days: 365 * 5).inMilliseconds;
      expect(RetentionPolicy.fromContent(content(ceiling)), isNotNull);
      expect(RetentionPolicy.fromContent(content(ceiling + 1)), isNull);
      expect(
        RetentionPolicy.fromContent(
          content(const Duration(days: 365 * 6).inMilliseconds),
        ),
        isNull,
      );
    });

    test('only an integer lifetime counts', () {
      expect(RetentionPolicy.fromContent(content(86400000.0)), isNull);
      expect(RetentionPolicy.fromContent(content('86400000')), isNull);
      expect(RetentionPolicy.fromContent(content(null)), isNull);
      expect(RetentionPolicy.fromContent({'expire_on_clients': true}), isNull);
    });

    test('expire_on_clients has to be true', () {
      expect(
        RetentionPolicy.fromContent(content(86400000, expire: null)),
        isNull,
      );
      expect(
        RetentionPolicy.fromContent(content(86400000, expire: false)),
        isNull,
      );
      expect(
        RetentionPolicy.fromContent(content(86400000, expire: 'true')),
        isNull,
      );
    });

    test('no content, or an empty one, is no policy', () {
      expect(RetentionPolicy.fromContent(null), isNull);
      expect(RetentionPolicy.fromContent({}), isNull);
    });

    test('extra keys are ignored', () {
      final extra = {...content(86400000), 'min_lifetime': 5, 'x': 'y'};
      expect(RetentionPolicy.fromContent(extra), isNotNull);
    });
  });

  group('stateOf', () {
    test('no content or an empty one is off', () {
      expect(RetentionPolicy.stateOf(null), RetentionState.off);
      expect(RetentionPolicy.stateOf({}), RetentionState.off);
    });

    test('a usable policy is applied', () {
      expect(
        RetentionPolicy.stateOf(content(86400000)),
        RetentionState.applied,
      );
    });

    test('content this app does not apply is another rule, not off', () {
      for (final foreign in <Map<String, Object?>>[
        {'max_lifetime': 86400000},
        {'max_lifetime': 86400000, 'expire_on_clients': false},
        {'max_lifetime': 1800000, 'expire_on_clients': true},
        {'max_lifetime': 1000 * 86400000 * 365 * 6, 'expire_on_clients': true},
        {'max_lifetime': '86400000', 'expire_on_clients': true},
        {'min_lifetime': 5},
        {'something': 'else'},
      ]) {
        expect(
          RetentionPolicy.stateOf(foreign),
          RetentionState.elsewhere,
          reason: '$foreign',
        );
      }
    });
  });

  group('contentFor', () {
    test('a lifetime keeps the keys it does not know', () {
      expect(
        RetentionPolicy.contentFor(
          day,
          existing: {'min_lifetime': 5, 'max_lifetime': 1, 'x': 'y'},
        ),
        {
          'min_lifetime': 5,
          'x': 'y',
          'max_lifetime': 86400000,
          'expire_on_clients': true,
        },
      );
    });

    test('off removes only the keys of this app', () {
      expect(
        RetentionPolicy.contentFor(
          null,
          existing: {
            'min_lifetime': 5,
            'max_lifetime': 86400000,
            'expire_on_clients': true,
          },
        ),
        {'min_lifetime': 5},
      );
      expect(
        RetentionPolicy.contentFor(null, existing: {'max_lifetime': 1}),
        isEmpty,
      );
    });

    test('off is an empty content', () {
      expect(RetentionPolicy.contentFor(null), isEmpty);
    });

    test('a timer asks clients to hide', () {
      expect(RetentionPolicy.contentFor(day), {
        'max_lifetime': 86400000,
        'expire_on_clients': true,
      });
    });

    test('what is written is read back', () {
      for (final lifetime in [
        ...RetentionPolicy.presets,
        const Duration(days: 90),
      ]) {
        expect(
          RetentionPolicy.fromContent(
            RetentionPolicy.contentFor(lifetime),
          )!.maxLifetime,
          lifetime,
        );
      }
    });
  });

  group('hides', () {
    const policy = RetentionPolicy(day);

    test('exactly at the boundary the message is hidden', () {
      expect(policy.hides(event(now.subtract(day)), now), isTrue);
    });

    test('one millisecond before it stays', () {
      final at = now.subtract(day).add(const Duration(milliseconds: 1));
      expect(policy.hides(event(at), now), isFalse);
    });

    test('state events are never hidden', () {
      final old = now.subtract(const Duration(days: 30));
      for (final type in [
        EventTypes.RoomName,
        EventTypes.RoomMember,
        RetentionPolicy.eventType,
        EventTypes.RoomCreate,
      ]) {
        expect(
          policy.hides(event(old, type: type), now),
          isFalse,
          reason: type,
        );
      }
    });

    test('messages that are not delivered yet are never hidden', () {
      final old = now.subtract(const Duration(days: 30));
      for (final status in [
        EventStatus.sending,
        EventStatus.error,
        EventStatus.sent,
      ]) {
        expect(
          policy.hides(event(old, status: status), now),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('an event from the future is not hidden', () {
      expect(
        policy.hides(event(now.add(const Duration(days: 2))), now),
        isFalse,
      );
    });

    test('messages, stickers, encrypted events and polls are hidden', () {
      final old = now.subtract(const Duration(days: 30));
      for (final type in [
        EventTypes.Message,
        EventTypes.Sticker,
        EventTypes.Encrypted,
        PollEventContent.startType,
      ]) {
        expect(policy.hides(event(old, type: type), now), isTrue, reason: type);
      }
    });

    test('the server timestamp decides, not the time of this check', () {
      final at = now.subtract(const Duration(hours: 23));
      expect(policy.hides(event(at), now), isFalse);
      expect(
        policy.hides(event(at), now.add(const Duration(hours: 2))),
        isTrue,
      );
    });
  });

  group('nextExpiry', () {
    const policy = RetentionPolicy(day);

    test('the earliest future expiry wins', () {
      final soon = event(now.subtract(const Duration(hours: 20)), id: r'$s:e');
      final later = event(now.subtract(const Duration(hours: 2)), id: r'$l:e');
      expect(
        policy.nextExpiry([later, soon], now),
        now.add(const Duration(hours: 4)),
      );
    });

    test('expired messages are ignored', () {
      final gone = event(now.subtract(const Duration(days: 3)));
      final fresh = event(now.subtract(const Duration(hours: 2)), id: r'$f:e');
      expect(
        policy.nextExpiry([gone, fresh], now),
        now.add(const Duration(hours: 22)),
      );
    });

    test('nothing to wait for', () {
      expect(policy.nextExpiry([], now), isNull);
      expect(
        policy.nextExpiry([event(now.subtract(const Duration(days: 3)))], now),
        isNull,
      );
    });

    test('more than a day away is not scheduled', () {
      const week = RetentionPolicy(Duration(days: 7));
      expect(week.nextExpiry([event(now)], now), isNull);
    });

    test('state events and unsent messages do not count', () {
      final state = event(now, type: EventTypes.RoomName);
      final unsent = event(now, status: EventStatus.sending);
      expect(policy.nextExpiry([state, unsent], now), isNull);
    });
  });
}
