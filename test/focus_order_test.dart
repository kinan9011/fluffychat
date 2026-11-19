// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/widgets/layouts/two_column_layout.dart';

Widget _column(String name) => Column(
  children: [
    for (final item in ['1', '2'])
      Focus(
        child: Builder(
          builder: (context) => Text(
            '$name$item${Focus.of(context).hasFocus ? ' *' : ''}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
  ],
);

void main() {
  testWidgets('Tab walks the rail, then the list, then the conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TwoColumnLayout(
          rail: _column('rail'),
          mainView: _column('list'),
          sideView: _column('chat'),
        ),
      ),
    );
    final visited = <String>[];
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = find.textContaining(' *');
      visited.add(
        focused.evaluate().isEmpty
            ? '-'
            : (focused.evaluate().first.widget as Text).data!.replaceAll(
                ' *',
                '',
              ),
      );
    }
    expect(visited, ['rail1', 'rail2', 'list1', 'list2', 'chat1', 'chat2']);
  });

  testWidgets('Shift+Tab walks back the same way', (tester) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TwoColumnLayout(
          rail: _column('rail'),
          mainView: _column('list'),
          sideView: _column('chat'),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pump();
    final visited = <String>[];
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      visited.add(
        (find.textContaining(' *').evaluate().first.widget as Text).data!
            .replaceAll(' *', ''),
      );
    }
    expect(visited, ['chat1', 'list2', 'list1']);
  });

  testWidgets('every column is its own traversal group', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TwoColumnLayout(
          rail: _column('rail'),
          mainView: _column('list'),
          sideView: _column('chat'),
        ),
      ),
    );
    final groups = find.descendant(
      of: find.byType(TwoColumnLayout),
      matching: find.byType(FocusTraversalGroup),
    );
    expect(groups.evaluate().length, greaterThanOrEqualTo(3));
  });
}
