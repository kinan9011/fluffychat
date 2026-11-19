// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/chat/events/message_focus.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  setUpAll(prepareTestClient);

  Future<void> pump(
    WidgetTester tester,
    VoidCallback onOpen, {
    bool enabled = true,
    Widget child = const SizedBox(width: 120, height: 40, child: Text('hello')),
  }) => pumpGoldenWidget(
    tester,
    Center(
      child: MessageFocus(
        enabled: enabled,
        actionLabel: 'More options',
        onOpenMenu: onOpen,
        child: child,
      ),
    ),
  );

  testWidgets('Tab focuses the message and Enter opens the menu', (
    tester,
  ) async {
    var opened = 0;
    await pump(tester, () => opened++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
  });

  testWidgets('the context menu key and Shift+F10 open it too', (tester) async {
    var opened = 0;
    await pump(tester, () => opened++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(opened, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(opened, 2);
  });

  testWidgets('a plain F10 does nothing', (tester) async {
    var opened = 0;
    await pump(tester, () => opened++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(opened, 0);
  });

  testWidgets('a focused message shows a focus ring', (tester) async {
    await pump(tester, () {});
    Finder ring() => find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.position == DecorationPosition.foreground &&
          (widget.decoration as BoxDecoration).border != null,
    );
    expect(ring(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring(), findsOneWidget);
  });

  testWidgets('a screen reader gets the named action', (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await pump(tester, () => opened++);
    final node = tester.getSemantics(find.byType(MessageFocus));
    final ids = node.getSemanticsData().customSemanticsActionIds!;
    final action = ids
        .map((id) => CustomSemanticsAction.getAction(id)!)
        .singleWhere((action) => action.label == 'More options');
    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(action),
    );
    expect(opened, 1);
    semantics.dispose();
  });

  testWidgets('disabled: no focus, no keys, no action', (tester) async {
    var opened = 0;
    await pump(tester, () => opened++, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 0);
    expect(
      tester
          .widgetList<Focus>(
            find.descendant(
              of: find.byType(MessageFocus),
              matching: find.byType(Focus),
            ),
          )
          .any((focus) => focus.canRequestFocus),
      isFalse,
    );
  });

  Widget buttonBubble(VoidCallback onPressed) => SizedBox(
    width: 160,
    height: 60,
    child: TextButton(onPressed: onPressed, child: const Text('Why?')),
  );

  testWidgets('Enter on a button inside the bubble activates that button, '
      'not the menu (REV N1)', (tester) async {
    var opened = 0;
    var pressed = 0;
    await pump(tester, () => opened++, child: buttonBubble(() => pressed++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect([pressed, opened], [1, 0]);
  });

  testWidgets('the context menu key on an inner button does not open the '
      'menu either (REV N1)', (tester) async {
    var opened = 0;
    await pump(tester, () => opened++, child: buttonBubble(() {}));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(opened, 0);
  });

  testWidgets('the focus ring is only on the bubble itself (REV N1)', (
    tester,
  ) async {
    await pump(tester, () {}, child: buttonBubble(() {}));
    Finder ring() => find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.position == DecorationPosition.foreground &&
          (widget.decoration as BoxDecoration).border != null,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring(), findsNothing);
  });

  testWidgets('holding Enter opens the menu once (REV N3)', (tester) async {
    var opened = 0;
    await pump(tester, () => opened++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
  });

  testWidgets('turning it off and on keeps the child alive (REV N2)', (
    tester,
  ) async {
    await pump(tester, () {}, child: const _Counter());
    final before = tester.state(find.byType(_Counter));
    await pump(tester, () {}, enabled: false, child: const _Counter());
    expect(tester.state(find.byType(_Counter)), same(before));
    await pump(tester, () {}, child: const _Counter());
    expect(tester.state(find.byType(_Counter)), same(before));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 50, height: 20);
}
