// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat_list/space_switcher.dart';
import 'package:odango/utils/chat_list/space_tabs_model.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

const _spaces = [
  SpaceTab(spaceId: '!a:x', name: 'Alpha', avatar: null, unread: 2),
  SpaceTab(spaceId: '!b:x', name: 'Beta', avatar: null, unread: 0),
];

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  var selected = <String?>[];
  var created = 0;
  var explored = 0;

  Widget chip({String? selectedSpaceId}) => SpaceSwitcherChip(
    client: client,
    spaces: _spaces,
    selectedSpaceId: selectedSpaceId,
    onSelect: selected.add,
    onCreateSpace: () => created++,
    onExplore: () => explored++,
  );

  setUp(() {
    selected = [];
    created = 0;
    explored = 0;
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(SpaceSwitcherChip));
    await tester.pumpAndSettle();
  }

  testWidgets('the chip shows All chats or the selected space', (tester) async {
    await pumpGoldenWidget(tester, chip());
    expect(find.text('All chats'), findsOneWidget);
    await pumpGoldenWidget(tester, chip(selectedSpaceId: '!b:x'));
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('All chats'), findsNothing);
  });

  testWidgets('the menu lists all chats, spaces and both actions', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, chip(selectedSpaceId: '!a:x'));
    await openMenu(tester);
    expect(find.text('SWITCH SPACE'), findsOneWidget);
    expect(find.text('All chats'), findsOneWidget);
    expect(find.text('Alpha'), findsNWidgets(2));
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('New space'), findsOneWidget);
    expect(find.text('Explore public spaces'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping a space selects it and closes the menu', (tester) async {
    await pumpGoldenWidget(tester, chip());
    await openMenu(tester);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(selected, ['!b:x']);
    expect(find.text('SWITCH SPACE'), findsNothing);
  });

  testWidgets('tapping All chats selects null', (tester) async {
    await pumpGoldenWidget(tester, chip(selectedSpaceId: '!a:x'));
    await openMenu(tester);
    await tester.tap(find.text('All chats'));
    await tester.pumpAndSettle();
    expect(selected, [null]);
  });

  testWidgets('create and explore call their callbacks', (tester) async {
    await pumpGoldenWidget(tester, chip(), size: const Size(400, 600));
    await openMenu(tester);
    await tester.tap(find.text('New space'));
    await tester.pumpAndSettle();
    await openMenu(tester);
    await tester.tap(find.text('Explore public spaces'));
    await tester.pumpAndSettle();
    expect([created, explored], [1, 1]);
  });

  testWidgets('Escape closes the menu', (tester) async {
    await pumpGoldenWidget(tester, chip());
    await openMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('SWITCH SPACE'), findsNothing);
    expect(selected, isEmpty);
  });

  testWidgets('reduce transparency makes the menu solid', (tester) async {
    await pumpGoldenWidget(tester, chip());
    await AppSettings.reduceTransparency.setItem(true);
    await openMenu(tester);
    expect(find.byType(BackdropFilter), findsNothing);
    await AppSettings.reduceTransparency.setItem(false);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('semantics: chip is a labelled button, rows know the current', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(tester, chip(selectedSpaceId: '!a:x'));
    expect(find.bySemanticsLabel('Alpha, switch space'), findsOneWidget);
    await openMenu(tester);
    expect(find.bySemanticsLabel('Alpha, 2 unread'), findsOneWidget);
    expect(find.bySemanticsLabel('Beta'), findsOneWidget);
    handle.dispose();
  });

  for (final rtl in [false, true]) {
    testWidgets('the menu opens under the chip (rtl: $rtl)', (tester) async {
      await pumpGoldenWidget(
        tester,
        Align(
          alignment: rtl ? Alignment.topRight : Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 100, right: 100, top: 20),
            child: chip(),
          ),
        ),
        rtl: rtl,
        size: const Size(500, 560),
      );
      final chipRect = tester.getRect(find.byType(SpaceSwitcherChip));
      await openMenu(tester);
      final card = tester.getRect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 290),
      );
      expect(
        rtl ? card.right : card.left,
        rtl ? chipRect.right : chipRect.left,
      );
      expect(card.top, chipRect.bottom + 6);
    });
  }

  testWidgets('the menu stays on screen next to the edge', (tester) async {
    await pumpGoldenWidget(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: Padding(padding: const EdgeInsets.only(top: 20), child: chip()),
      ),
      size: const Size(400, 560),
    );
    await openMenu(tester);
    final card = tester.getRect(
      find.byWidgetPredicate((w) => w is SizedBox && w.width == 290),
    );
    expect(card.right, lessThanOrEqualTo(400 - 12));
    expect(card.left, greaterThanOrEqualTo(12));
  });

  testWidgets('goldens: menu in light, dark and RTL', (tester) async {
    for (final variant in goldenVariants) {
      await pumpGoldenWidget(
        tester,
        chip(selectedSpaceId: '!a:x'),
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: variant.locale,
        size: const Size(400, 560),
      );
      await openMenu(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/space_switcher_menu_${variant.suffix}.png'),
      );
    }
  });
}
