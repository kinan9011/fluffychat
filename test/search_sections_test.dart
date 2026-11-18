// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/local_search.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/utils/search/search_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chip to filter', () {
    test('Media, Files and Links set the type facet', () {
      const none = MessageSearchFilter.none;
      expect(
        SearchSections.select(
          SearchSection.media,
          none,
          SearchSection.all,
        ).types,
        {SearchType.photos, SearchType.videos},
      );
      expect(
        SearchSections.select(
          SearchSection.files,
          none,
          SearchSection.all,
        ).types,
        {SearchType.files},
      );
      expect(
        SearchSections.select(
          SearchSection.links,
          none,
          SearchSection.all,
        ).types,
        {SearchType.links},
      );
    });

    test('the other facets stay when a type chip is chosen', () {
      final filter = const MessageSearchFilter().copyWith(
        fromIds: {'@a:example.org'},
        mentionsMe: true,
      );
      final next = SearchSections.select(
        SearchSection.files,
        filter,
        SearchSection.all,
      );
      expect(next.fromIds, {'@a:example.org'});
      expect(next.mentionsMe, isTrue);
    });

    test('leaving a type chip clears the types it set', () {
      final filter = const MessageSearchFilter().copyWith(
        types: {SearchType.files},
      );
      expect(
        SearchSections.select(
          SearchSection.messages,
          filter,
          SearchSection.files,
        ).types,
        isEmpty,
      );
    });

    test('a chip that owns no types keeps what the sheet chose', () {
      final filter = const MessageSearchFilter().copyWith(
        types: {SearchType.voice},
      );
      expect(
        SearchSections.select(
          SearchSection.chats,
          filter,
          SearchSection.all,
        ).types,
        {SearchType.voice},
      );
    });
  });

  group('filter to chip', () {
    test('the sheet types that match a chip select it', () {
      MessageSearchFilter with_(Set<SearchType> types) =>
          const MessageSearchFilter().copyWith(types: types);
      expect(
        SearchSections.after(
          with_({SearchType.photos, SearchType.videos}),
          SearchSection.all,
        ),
        SearchSection.media,
      );
      expect(
        SearchSections.after(with_({SearchType.files}), SearchSection.all),
        SearchSection.files,
      );
      expect(
        SearchSections.after(with_({SearchType.links}), SearchSection.all),
        SearchSection.links,
      );
    });

    test('other types fall back to All when a type chip was selected', () {
      final filter = const MessageSearchFilter().copyWith(
        types: {SearchType.voice},
      );
      expect(
        SearchSections.after(filter, SearchSection.files),
        SearchSection.all,
      );
    });

    test('other types keep a chip that owns none', () {
      final filter = const MessageSearchFilter().copyWith(
        types: {SearchType.voice},
      );
      expect(
        SearchSections.after(filter, SearchSection.messages),
        SearchSection.messages,
      );
    });

    test('chip and sheet agree after a round trip', () {
      for (final section in [
        SearchSection.media,
        SearchSection.files,
        SearchSection.links,
      ]) {
        final filter = SearchSections.select(
          section,
          MessageSearchFilter.none,
          SearchSection.all,
        );
        expect(SearchSections.after(filter, SearchSection.all), section);
      }
    });
  });

  group('mergeMessages', () {
    SearchHit hit(int n, int ts, {String room = '!a:example.org'}) => SearchHit(
      IndexedMessage(
        roomId: room,
        eventId: '\$e$n:example.org',
        senderId: '@a:example.org',
        timestamp: ts,
        kind: SearchKind.text,
        text: 'x',
      ),
      const [],
    );

    test('newest first, every message once', () {
      final merged = SearchSections.mergeMessages(
        [hit(1, 10), hit(2, 30)],
        [hit(2, 30), hit(3, 20)],
      );
      expect(merged.map((h) => h.message.eventId), [
        r'$e2:example.org',
        r'$e3:example.org',
        r'$e1:example.org',
      ]);
    });

    test('the same event id in another room is another message', () {
      final merged = SearchSections.mergeMessages(
        [hit(1, 10)],
        [hit(1, 20, room: '!b:example.org')],
      );
      expect(merged.length, 2);
    });

    test('the list is capped at 200', () {
      final merged = SearchSections.mergeMessages([
        for (var n = 0; n < 300; n++) hit(n, n),
      ], const []);
      expect(merged.length, SearchSections.maxMessages);
      expect(merged.first.message.timestamp, 299);
    });
  });
}
