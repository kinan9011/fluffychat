// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/global_search/global_search.dart';
import 'package:odango/pages/global_search/global_search_view.dart';
import 'package:odango/pages/global_search/search_filter_sheet.dart';
import 'package:odango/pages/global_search/search_result_widgets.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/widgets/settings/settings_toggle_row.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';
import 'utils/search_fixtures.dart';

const _room = '!secret:example.org';

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
    final client = harness.client;
    harness.resetRooms();
    MessageIndex.forget(client);
    await client.database.cacheCustomObject(MessageIndex.documentKey, {
      'v': 1,
      'e': <Object?>[],
    });
  });
  tearDown(harness.tearDown);

  Future<void> fill(WidgetTester tester, {int messages = 12}) async {
    final room = searchRoom(harness.client, _room);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'A chat with a rather long name that has to wrap'},
        room: room,
        eventId: r'$name:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    harness.client.rooms.add(room);
    final index = MessageIndex.of(harness.client);
    await tester.runAsync(() => index.ready);
    for (var n = 0; n < messages; n++) {
      index.add(
        IndexedMessage(
          roomId: _room,
          eventId: '\$idx$n:example.org',
          senderId: '@alice:example.org',
          timestamp: DateTime.now()
              .subtract(Duration(minutes: n + 1))
              .millisecondsSinceEpoch,
          kind: SearchKind.text,
          text:
              'needle number $n in a long sentence that needs more than one line '
              'on a very narrow screen so that nothing may overflow here',
        ),
      );
    }
  }

  void smallScreen(WidgetTester tester, {double scale = 1.0}) {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('the page at 320x480 with the keyboard open and text x$scale', (
      tester,
    ) async {
      smallScreen(tester, scale: scale);
      await fill(tester);
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: '/rooms/search',
      );
      await tester.enterText(find.byKey(GlobalSearchView.fieldKey), 'needle');
      await tester.pump(const Duration(milliseconds: 350));
      await harness.settle(tester, rounds: 3);
      final field = tester.getRect(find.byKey(GlobalSearchView.fieldKey));
      expect(field.top, greaterThanOrEqualTo(0));
      expect(field.bottom, lessThanOrEqualTo(480 - 300 + 1));
      expect(field.height, greaterThanOrEqualTo(44));
      await tester.scrollUntilVisible(
        find.byType(MessageHitTile),
        100,
        scrollable: find.descendant(
          of: find.byKey(GlobalSearchView.resultsKey),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byType(MessageHitTile), findsWidgets);
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });
  }

  testWidgets(
    'the chips scroll sideways and every chip is at least 44 px high',
    (tester) async {
      smallScreen(tester);
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: '/rooms/search',
      );
      final chips = find.byType(SearchChip);
      expect(chips, findsWidgets);
      for (final chip in chips.evaluate()) {
        final size = tester.getSize(find.byWidget(chip.widget));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    },
  );

  testWidgets(
    'the filter sheet at 320x480 scrolls and keeps its buttons in reach',
    (tester) async {
      smallScreen(tester, scale: 2.0);
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: '/rooms/search',
      );
      await tester.tap(find.byKey(GlobalSearchView.filtersKey));
      await harness.settle(tester, rounds: 3);
      expect(find.byType(SearchFilterSheet), findsOneWidget);
      final apply = tester.getRect(find.byKey(SearchFilterSheet.applyKey));
      final reset = tester.getRect(find.byKey(SearchFilterSheet.resetKey));
      expect(apply.bottom, lessThanOrEqualTo(480 - 300 + 1));
      expect(apply.height, greaterThanOrEqualTo(44));
      expect(reset.height, greaterThanOrEqualTo(44));
      await tester.scrollUntilVisible(
        find.byType(SettingsToggleRow),
        100,
        scrollable: find
            .descendant(
              of: find.byType(SearchFilterSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    },
  );

  testWidgets('the chat picker of the sheet works with the keyboard open', (
    tester,
  ) async {
    smallScreen(tester);
    await fill(tester, messages: 1);
    await harness.open(tester, width: 320, height: 480, path: '/rooms/search');
    await tester.tap(find.byKey(GlobalSearchView.filtersKey));
    await harness.settle(tester, rounds: 3);
    final l10n = L10n.of(tester.element(find.byType(SearchFilterSheet)));
    await tester.ensureVisible(find.text(l10n.searchAddChat));
    await tester.pump();
    await tester.tap(find.text(l10n.searchAddChat));
    await harness.settle(tester, rounds: 3);
    final field = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(480 - 300 + 1));
    await tester.enterText(field, 'rather long');
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  testWidgets('GlobalSearch exists as a route page', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    expect(find.byType(GlobalSearch), findsOneWidget);
    await harness.finish(tester);
  });
}
