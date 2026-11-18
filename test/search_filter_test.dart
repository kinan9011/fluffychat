// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2031, 6, 15, 23, 59);

  IndexedMessage message({
    String room = '!a:example.org',
    String sender = '@alice:example.org',
    DateTime? at,
    SearchKind kind = SearchKind.text,
    bool mentions = false,
    bool link = false,
  }) => IndexedMessage(
    roomId: room,
    eventId: r'$e:example.org',
    senderId: sender,
    timestamp: (at ?? now).millisecondsSinceEpoch,
    kind: kind,
    text: 'x',
    mentionsMe: mentions,
    hasLink: link,
  );

  test('the empty filter matches everything and counts nothing', () {
    const filter = MessageSearchFilter.none;
    expect(filter.isEmpty, isTrue);
    expect(filter.activeCount, 0);
    expect(filter.matches(message(), now), isTrue);
  });

  test('from: only the chosen senders match', () {
    final filter = const MessageSearchFilter().copyWith(
      fromIds: {'@bob:example.org'},
    );
    expect(filter.matches(message(sender: '@bob:example.org'), now), isTrue);
    expect(filter.matches(message(), now), isFalse);
  });

  test('in: only the chosen chats match', () {
    final filter = const MessageSearchFilter().copyWith(
      inRoomIds: {'!b:example.org'},
    );
    expect(filter.matches(message(room: '!b:example.org'), now), isTrue);
    expect(filter.matches(message(), now), isFalse);
  });

  test('ids that are not user or room ids are dropped', () {
    final filter = const MessageSearchFilter().copyWith(
      fromIds: {'alice', '#room:example.org', '@ok:example.org'},
      inRoomIds: {'!x', r'$ev:example.org', '!ok:example.org'},
    );
    expect(filter.fromIds, {'@ok:example.org'});
    expect(filter.inRoomIds, {'!ok:example.org'});
  });

  test('at most 10 senders and 20 chats are kept', () {
    final filter = const MessageSearchFilter().copyWith(
      fromIds: {for (var i = 0; i < 30; i++) '@u$i:example.org'},
      inRoomIds: {for (var i = 0; i < 50; i++) '!r$i:example.org'},
    );
    expect(filter.fromIds.length, MessageSearchFilter.maxFrom);
    expect(filter.inRoomIds.length, MessageSearchFilter.maxRooms);
  });

  test('type filters', () {
    bool hit(SearchType type, SearchKind kind, {bool link = false}) =>
        const MessageSearchFilter()
            .copyWith(types: {type})
            .matches(message(kind: kind, link: link), now);
    expect(hit(SearchType.photos, SearchKind.image), isTrue);
    expect(hit(SearchType.photos, SearchKind.video), isFalse);
    expect(hit(SearchType.videos, SearchKind.video), isTrue);
    expect(hit(SearchType.files, SearchKind.file), isTrue);
    expect(hit(SearchType.files, SearchKind.audio), isTrue);
    expect(hit(SearchType.files, SearchKind.voice), isFalse);
    expect(hit(SearchType.voice, SearchKind.voice), isTrue);
    expect(hit(SearchType.polls, SearchKind.poll), isTrue);
    expect(hit(SearchType.links, SearchKind.text, link: true), isTrue);
    expect(hit(SearchType.links, SearchKind.text), isFalse);
  });

  test('several types match any of them', () {
    final filter = const MessageSearchFilter().copyWith(
      types: {SearchType.photos, SearchType.videos},
    );
    expect(filter.matches(message(kind: SearchKind.video), now), isTrue);
    expect(filter.matches(message(kind: SearchKind.file), now), isFalse);
  });

  test('mentions me', () {
    final filter = const MessageSearchFilter().copyWith(mentionsMe: true);
    expect(filter.matches(message(mentions: true), now), isTrue);
    expect(filter.matches(message(), now), isFalse);
  });

  group('dates', () {
    MessageSearchFilter on(DatePreset date, {DateWindow? custom}) =>
        const MessageSearchFilter().copyWith(date: date, custom: custom);

    test('today starts at local midnight (23:59 and 00:01)', () {
      final filter = on(DatePreset.today);
      final lateNow = DateTime(2031, 6, 15, 23, 59);
      expect(
        filter.matches(message(at: DateTime(2031, 6, 15, 0, 0, 1)), lateNow),
        isTrue,
      );
      expect(
        filter.matches(message(at: DateTime(2031, 6, 14, 23, 59)), lateNow),
        isFalse,
      );
      final earlyNow = DateTime(2031, 6, 15, 0, 1);
      expect(
        filter.matches(message(at: DateTime(2031, 6, 14, 23, 58)), earlyNow),
        isFalse,
      );
      expect(
        filter.matches(message(at: DateTime(2031, 6, 15)), earlyNow),
        isTrue,
      );
    });

    test('week is the last 7 days', () {
      final filter = on(DatePreset.week);
      expect(
        filter.matches(
          message(at: now.subtract(const Duration(days: 6, hours: 23))),
          now,
        ),
        isTrue,
      );
      expect(
        filter.matches(
          message(at: now.subtract(const Duration(days: 7, minutes: 1))),
          now,
        ),
        isFalse,
      );
    });

    test('month is the last 30 days', () {
      final filter = on(DatePreset.month);
      expect(
        filter.matches(
          message(at: now.subtract(const Duration(days: 29))),
          now,
        ),
        isTrue,
      );
      expect(
        filter.matches(
          message(at: now.subtract(const Duration(days: 31))),
          now,
        ),
        isFalse,
      );
    });

    test('custom covers whole local days, both ends inclusive', () {
      final window = MessageSearchFilter.window(
        DateTime(2031, 6, 10, 15),
        DateTime(2031, 6, 12, 3),
        now: now,
      )!;
      final filter = on(DatePreset.custom, custom: window);
      expect(
        filter.matches(message(at: DateTime(2031, 6, 10, 0, 0)), now),
        isTrue,
      );
      expect(
        filter.matches(message(at: DateTime(2031, 6, 12, 23, 59, 59)), now),
        isTrue,
      );
      expect(
        filter.matches(message(at: DateTime(2031, 6, 9, 23, 59)), now),
        isFalse,
      );
      expect(filter.matches(message(at: DateTime(2031, 6, 13)), now), isFalse);
    });

    test('a window with the end before the start is rejected', () {
      expect(
        MessageSearchFilter.window(
          DateTime(2031, 6, 12),
          DateTime(2031, 6, 10),
          now: now,
        ),
        isNull,
      );
    });

    test('a window is pulled inside 2000-01-01..tomorrow', () {
      final window = MessageSearchFilter.window(
        DateTime(1970),
        DateTime(2099),
        now: now,
      )!;
      expect(window.start, DateTime(2000));
      expect(window.end.isAfter(now.add(const Duration(days: 2))), isFalse);
    });

    test('custom without a window is no filter at all', () {
      final filter = on(DatePreset.custom);
      expect(filter.isEmpty, isTrue);
      expect(filter.activeCount, 0);
      expect(filter.matches(message(at: DateTime(2001)), now), isTrue);
    });
  });

  test('activeCount counts facet groups, not values', () {
    final filter = const MessageSearchFilter().copyWith(
      fromIds: {'@a:example.org', '@b:example.org'},
      inRoomIds: {'!a:example.org'},
      date: DatePreset.week,
      types: {SearchType.files, SearchType.links},
      mentionsMe: true,
    );
    expect(filter.activeCount, 5);
  });

  test('equal filters are equal regardless of set order', () {
    final a = const MessageSearchFilter().copyWith(
      fromIds: {'@a:example.org', '@b:example.org'},
    );
    final b = const MessageSearchFilter().copyWith(
      fromIds: {'@b:example.org', '@a:example.org'},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
