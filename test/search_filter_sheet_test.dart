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
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/search_filter.dart';
import 'package:odango/utils/search/search_kind.dart';
import 'package:odango/utils/search/search_sections.dart';
import 'package:odango/widgets/settings/settings_toggle_row.dart';

import 'utils/chat_page_harness.dart';
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
    final client = harness.client;
    harness.resetRooms();
    MessageIndex.forget(client);
    await client.database.cacheCustomObject(MessageIndex.documentKey, {
      'v': 1,
      'e': <Object?>[],
    });
  });
  tearDown(harness.tearDown);

  GlobalSearchController controller(WidgetTester tester) =>
      tester.state<GlobalSearchController>(find.byType(GlobalSearch));

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(GlobalSearch)));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(GlobalSearchView.filtersKey));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(SearchFilterSheet), findsOneWidget);
  }

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(SearchFilterSheet), matching: finder);

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(inSheet(finder));
    await tester.pump();
    await tester.tap(inSheet(finder));
    await tester.pump();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.byKey(SearchFilterSheet.applyKey));
    await harness.settle(tester, rounds: 3);
  }

  testWidgets('types are multi select and the primary button applies them', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    final text = l10n(tester);
    await tapInSheet(tester, find.text(text.searchTypeVoice));
    await tapInSheet(tester, find.text(text.searchTypePolls));
    await apply(tester);
    expect(controller(tester).filter.types, {
      SearchType.voice,
      SearchType.polls,
    });
    expect(controller(tester).filter.activeCount, 1);
    expect(controller(tester).section, SearchSection.all);
    await harness.finish(tester);
  });

  testWidgets('Files in the sheet selects the Files chip', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchTypeFiles));
    await apply(tester);
    expect(controller(tester).section, SearchSection.files);
    await harness.finish(tester);
  });

  testWidgets('the mentions switch is part of the filter', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.byType(SettingsToggleRow));
    await apply(tester);
    expect(controller(tester).filter.mentionsMe, isTrue);
    await harness.finish(tester);
  });

  testWidgets('Reset empties the draft before it is applied', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchTypeVoice));
    await tester.tap(find.byKey(SearchFilterSheet.resetKey));
    await tester.pump();
    await apply(tester);
    expect(controller(tester).filter.isEmpty, isTrue);
    await harness.finish(tester);
  });

  testWidgets('closing the sheet keeps the filter that was set before', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchTypeVoice));
    await apply(tester);
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchTypePolls));
    await tester.tap(find.byTooltip(l10n(tester).close));
    await harness.settle(tester, rounds: 3);
    expect(controller(tester).filter.types, {SearchType.voice});
    await harness.finish(tester);
  });

  testWidgets('Anyone clears the senders', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchAnyone));
    await apply(tester);
    expect(controller(tester).filter.fromIds, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('Custom opens the date picker and cancelling keeps the date', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).custom));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byTooltip(
          MaterialLocalizations.of(
            tester.element(find.byType(DateRangePickerDialog)),
          ).closeButtonTooltip,
        ),
      ),
    );
    await harness.settle(tester, rounds: 3);
    await apply(tester);
    expect(controller(tester).filter.effectiveDate, DatePreset.any);
    await harness.finish(tester);
  });

  testWidgets('Today and Week are plain date presets', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchWeek));
    await apply(tester);
    expect(controller(tester).filter.date, DatePreset.week);
    await harness.finish(tester);
  });

  testWidgets('the chip row and the sheet agree', (tester) async {
    await harness.open(tester, path: '/rooms/search');
    controller(tester).selectSection(SearchSection.links);
    await harness.settle(tester, rounds: 2);
    await openSheet(tester);
    final chip = inSheet(find.bySemanticsLabel(l10n(tester).searchTypeLinks));
    expect(chip, findsWidgets);
    await apply(tester);
    expect(controller(tester).filter.types, {SearchType.links});
    expect(controller(tester).section, SearchSection.links);
    await harness.finish(tester);
  });

  testWidgets('the chat picker lists chats, not spaces', (tester) async {
    final client = harness.client;
    final space = Room(
      id: '!space:example.org',
      client: client,
      membership: Membership.join,
    );
    space.setState(
      Event(
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': RoomCreationTypes.mSpace},
        room: space,
        eventId: r'$create:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    space.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Neighbourhood space'},
        room: space,
        eventId: r'$sname:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    final chat = searchRoom(client, '!chat:example.org', encrypted: false);
    chat.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Neighbourhood chat'},
        room: chat,
        eventId: r'$cname:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
    client.rooms.addAll([space, chat]);
    expect(space.isSpace, isTrue);
    await harness.open(tester, path: '/rooms/search');
    await openSheet(tester);
    await tapInSheet(tester, find.text(l10n(tester).searchAddChat));
    await harness.settle(tester, rounds: 3);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Neighbourhood chat'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Neighbourhood space'),
      ),
      findsNothing,
    );
    await harness.finish(tester);
  });
}
