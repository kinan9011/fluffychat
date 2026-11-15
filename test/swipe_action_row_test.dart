// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/swipe_action_row.dart';
import 'package:fluffychat/utils/chat_list/swipe_actions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late List<(String, SwipeAction)> runs;
  late ValueNotifier<String?> openRow;

  setUpAll(() async => client = await prepareTestClient());

  setUp(() {
    runs = [];
    openRow = ValueNotifier(null);
  });

  ChatRowActions actions() => ChatRowActions(
    openRow: openRow,
    run: (id, action) async => runs.add((id, action)),
    more: (_, _) {},
  );

  Widget swipeRow(
    String id, {
    bool unread = true,
    bool muted = false,
    bool pinned = false,
    bool archived = false,
  }) => SwipeActionRow(
    key: ValueKey('swipe_$id'),
    roomId: id,
    actions: actions(),
    unread: unread,
    muted: muted,
    pinned: pinned,
    archived: archived,
    child: SizedBox(height: 76, child: Center(child: Text('row $id'))),
  );

  Future<void> pumpRows(
    WidgetTester tester,
    List<Widget> rows, {
    bool rtl = false,
    bool disableAnimations = false,
  }) => pumpGoldenWidget(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    ),
    rtl: rtl,
    size: const Size(400, 400),
  );

  Finder rowFinder(String id) => find.byKey(ValueKey('swipe_$id'));

  Finder tray(String id, String key) =>
      find.descendant(of: rowFinder(id), matching: find.byKey(ValueKey(key)));

  testWidgets('a long swipe opens the tray with three labelled buttons', (
    tester,
  ) async {
    await pumpRows(tester, [swipeRow('!a:x')]);
    await tester.drag(rowFinder('!a:x'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(openRow.value, '!a:x');
  });

  testWidgets('tapping Archive runs it for this room and closes the tray', (
    tester,
  ) async {
    await pumpRows(tester, [swipeRow('!a:x')]);
    await tester.drag(rowFinder('!a:x'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    await tester.tap(tray('!a:x', 'swipe_archive'));
    await tester.pumpAndSettle();
    expect(runs, [('!a:x', SwipeAction.archive)]);
    expect(find.text('Archive'), findsNothing);
  });

  testWidgets('labels follow the state of the chat', (tester) async {
    await pumpRows(tester, [
      swipeRow('!a:x', muted: true, pinned: true, archived: true),
    ]);
    await tester.drag(rowFinder('!a:x'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Unmute'), findsOneWidget);
    expect(find.text('Unpin'), findsOneWidget);
    expect(find.text('Unarchive'), findsOneWidget);
  });

  testWidgets('a short swipe closes again and runs nothing', (tester) async {
    await pumpRows(tester, [swipeRow('!a:x')]);
    await tester.drag(rowFinder('!a:x'), const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsNothing);
    expect(runs, isEmpty);
    expect(openRow.value, isNull);
  });

  testWidgets('swiping right past the threshold toggles read', (tester) async {
    await pumpRows(tester, [swipeRow('!a:x')]);
    await tester.drag(rowFinder('!a:x'), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(runs, [('!a:x', SwipeAction.toggleRead)]);
    await tester.drag(rowFinder('!a:x'), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(runs, hasLength(1));
  });

  testWidgets('RTL flips the directions', (tester) async {
    await pumpRows(tester, [swipeRow('!a:x')], rtl: true);
    await tester.drag(rowFinder('!a:x'), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(runs, [('!a:x', SwipeAction.toggleRead)]);
    await tester.drag(rowFinder('!a:x'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    expect(tester.getTopLeft(tray('!a:x', 'swipe_mute')).dx, lessThan(200));
  });

  testWidgets('a mouse drag does nothing', (tester) async {
    await pumpRows(tester, [swipeRow('!a:x')]);
    final gesture = await tester.startGesture(
      tester.getCenter(rowFinder('!a:x')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-250, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsNothing);
    expect(runs, isEmpty);
  });

  testWidgets('with disabled animations nothing keeps running', (tester) async {
    await pumpRows(tester, [swipeRow('!a:x')], disableAnimations: true);
    await tester.drag(rowFinder('!a:x'), const Offset(-250, 0));
    await tester.pump();
    expect(find.text('Archive'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(tray('!a:x', 'swipe_archive'));
    await tester.pump();
    expect(find.text('Archive'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('opening a row closes the one that was open', (tester) async {
    await pumpRows(tester, [swipeRow('!a:x'), swipeRow('!b:x')]);
    await tester.drag(rowFinder('!a:x'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(tray('!a:x', 'swipe_archive'), findsOneWidget);
    await tester.drag(rowFinder('!b:x'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(tray('!b:x', 'swipe_archive'), findsOneWidget);
    expect(tray('!a:x', 'swipe_archive'), findsNothing);
  });

  testWidgets('a row reused for another chat starts closed', (tester) async {
    Widget row(String id) => SwipeActionRow(
      roomId: id,
      actions: actions(),
      unread: false,
      muted: false,
      pinned: false,
      archived: false,
      child: const SizedBox(height: 76, child: Text('row')),
    );
    await pumpRows(tester, [row('!a:x')]);
    await tester.drag(find.byType(SwipeActionRow), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    await pumpRows(tester, [row('!b:x')]);
    expect(find.text('Archive'), findsNothing);
  });

  testWidgets('clearing the open row (a scroll) closes the tray', (
    tester,
  ) async {
    await pumpRows(tester, [swipeRow('!a:x')]);
    await tester.drag(rowFinder('!a:x'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    openRow.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsNothing);
  });

  testWidgets('an open tray absorbs a tap on the row and closes', (
    tester,
  ) async {
    var taps = 0;
    await pumpGoldenWidget(
      tester,
      SwipeActionRow(
        roomId: '!a:x',
        actions: actions(),
        unread: false,
        muted: false,
        pinned: false,
        archived: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox(height: 76, width: 400),
        ),
      ),
    );
    await tester.drag(find.byType(SwipeActionRow), const Offset(-250, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(find.text('Archive'), findsNothing);
    await tester.tapAt(const Offset(20, 30));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
  });

  group('semantics custom actions', () {
    Future<void> pumpItem(WidgetTester tester, Room room) => pumpGoldenWidget(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: ChatListItem(room, onTap: () {}, actions: actions()),
      ),
      size: const Size(400, 400),
    ).then((_) => tester.pump(const Duration(seconds: 35)));

    testWidgets('the row exposes the five actions and runs them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final room = testChat(
        client,
        '!a:x',
        name: 'Anna',
        unread: 2,
        lastBody: 'Hi',
      );
      client.rooms.add(room);
      addTearDown(() => client.rooms.remove(room));
      await pumpItem(tester, room);
      final node = tester.getSemantics(
        find.descendant(
          of: find.byType(ChatListItem),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label?.startsWith('Anna') == true,
          ),
        ),
      );
      final data = node.getSemanticsData();
      final ids = data.customSemanticsActionIds!;
      final labels = {
        for (final id in ids) CustomSemanticsAction.getAction(id)!.label: id,
      };
      expect(labels.keys.toSet(), {
        'Mute',
        'Pin',
        'Archive',
        'Mark as read',
        'More options',
      });
      tester.semantics.performAction(
        find.semantics.byLabel(RegExp('^Anna')),
        SemanticsAction.customAction,
        args: labels['Archive'],
      );
      await tester.pump();
      expect(runs, [('!a:x', SwipeAction.archive)]);
      handle.dispose();
    });

    testWidgets('an invite and a left room have no swipe actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final invite = testChat(
        client,
        '!i:x',
        name: 'Ivy',
        membership: Membership.invite,
      );
      await pumpItem(tester, invite);
      expect(find.byType(SwipeActionRow), findsNothing);
      handle.dispose();
    });
  });
}
