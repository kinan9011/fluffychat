// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/global_search/global_search_view.dart';
import 'package:fluffychat/pages/global_search/search_filter_sheet.dart';
import 'package:fluffychat/pages/global_search/search_result_widgets.dart';
import 'package:fluffychat/utils/search/indexed_message.dart';
import 'package:fluffychat/utils/search/message_index.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/utils/search/search_sections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/golden.dart';
import 'utils/recording_api.dart';
import 'utils/search_fixtures.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': <Object?>[],
      'limited': false,
    };
    api.api['POST']!['/client/v3/publicRooms'] = (_) => {
      'chunk': <Object?>[],
      'total_room_count_estimate': 0,
    };
    api.api['POST']!['/client/v3/search'] = (_) => {
      'search_categories': {
        'room_events': {'count': 0, 'results': <Object?>[]},
      },
    };
    final client = harness.client;
    harness.resetRooms();
    MessageIndex.forget(client);
    await client.database.cacheCustomObject(MessageIndex.documentKey, {
      'v': 1,
      'e': <Object?>[],
    });
  });
  tearDown(harness.tearDown);

  testWidgets('chips goldens in light, dark and RTL', (tester) async {
    await expectGoldenVariants(
      tester,
      'search_chips',
      Material(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SearchChipsBar(selected: SearchSection.files, onSelect: (_) {}),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                children: [
                  SearchChip(label: 'Mara', selected: true, onTap: () {}),
                  SearchChip(
                    label: 'Files',
                    selected: false,
                    icon: Icons.description_outlined,
                    onTap: () {},
                  ),
                  SearchChip(
                    label: 'Design crew',
                    selected: true,
                    onTap: () {},
                    onClose: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      size: const Size(400, 200),
    );
  });

  for (final variant in goldenVariants) {
    testWidgets('page golden ${variant.suffix}', (tester) async {
      final room = searchRoom(harness.client, '!secret:example.org');
      room.setState(
        Event(
          type: EventTypes.RoomName,
          stateKey: '',
          content: {'name': 'Matrix HQ'},
          room: room,
          eventId: r'$name:example.org',
          senderId: '@alice:example.org',
          originServerTs: DateTime(2025),
        ),
      );
      harness.client.rooms.add(room);
      final index = MessageIndex.of(harness.client);
      await tester.runAsync(() => index.ready);
      for (final (n, text) in [
        'Jonas: 2.1 RC is tagged, release notes are in the thread',
        'You: Can we move the release to Friday?',
      ].indexed) {
        index.add(
          IndexedMessage(
            roomId: '!secret:example.org',
            eventId: '\$g$n:example.org',
            senderId: '@alice:example.org',
            timestamp: DateTime(2031, 6, 15, 12 - n, 10).millisecondsSinceEpoch,
            kind: SearchKind.text,
            text: text,
          ),
        );
      }
      await harness.open(
        tester,
        path: '/rooms/search',
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'release');
      await tester.pump(const Duration(milliseconds: 350));
      await harness.settle(tester, rounds: 3);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/global_search_${variant.suffix}.png'),
      );
      await harness.finish(tester);
    });
  }

  for (final variant in goldenVariants) {
    testWidgets('filter sheet golden ${variant.suffix}', (tester) async {
      await harness.open(
        tester,
        height: 800,
        path: '/rooms/search',
        brightness: variant.brightness,
        locale: variant.rtl ? variant.locale : null,
      );
      await tester.tap(find.byKey(GlobalSearchView.filtersKey));
      await harness.settle(tester, rounds: 3);
      await tester.tap(
        find.descendant(
          of: find.byType(SearchFilterSheet),
          matching: find.byIcon(Icons.description_outlined),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/search_filter_sheet_${variant.suffix}.png'),
      );
      await harness.finish(tester);
    });
  }
}
