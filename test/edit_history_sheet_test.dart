// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/pages/chat/edit_history_sheet.dart';
import 'package:fluffychat/utils/chat/edit_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/golden.dart';

EditVersion version(String id, int ts, String text) => EditVersion(
  eventId: id,
  time: DateTime.utc(2026, 1, 1, 12, ts),
  text: text,
);

final mockup = EditHistory(
  original: version(r'$o', 42, 'Testing it now, results in an hour.'),
  edits: [
    version(r'$a', 43, 'Testing it now, results in 20 minutes.'),
    version(r'$b', 44, 'Testing it now, results in 20 minutes. Thanks'),
  ],
);

Widget view({
  EditHistory? history,
  bool loading = false,
  VoidCallback? onEditAgain,
  VoidCallback? onDelete,
  VoidCallback? onClose,
}) => EditHistoryView(
  history: history,
  loading: loading,
  onClose: onClose ?? () {},
  onEditAgain: onEditAgain,
  onDelete: onDelete,
);

TextStyle? styleOf(WidgetTester tester, Finder within, String text) {
  TextStyle? found;
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = inherited == null ? span.style : inherited.merge(span.style);
    if (span.text == text) found = style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, style);
    }
  }

  for (final richText in tester.widgetList<RichText>(
    find.descendant(of: within, matching: find.byType(RichText)),
  )) {
    walk(richText.text, null);
  }
  return found;
}

void main() {
  testWidgets('current, edited and original in that order with times', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      view(history: mockup),
      size: const Size(400, 800),
    );
    final labels = [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if (text.data != null &&
            RegExp(r'^(CURRENT|EDITED|ORIGINAL) · ').hasMatch(text.data!))
          text.data!,
    ];
    expect(labels.length, 4);
    expect(labels[0], startsWith('CURRENT · '));
    expect(labels[1], startsWith('EDITED · '));
    expect(labels[2], startsWith('EDITED · '));
    expect(labels[3], startsWith('ORIGINAL · '));
    expect(find.text('Edit history'), findsOneWidget);
  });

  testWidgets('a message edited once shows what that edit changed', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      view(
        history: EditHistory(
          original: version(r'$o', 1, 'see you at noon'),
          edits: [version(r'$a', 2, 'see you at one')],
        ),
      ),
      size: const Size(400, 800),
    );
    final edited = find.byKey(const ValueKey('history_1'));
    expect(
      styleOf(tester, edited, 'noon')?.decoration,
      TextDecoration.lineThrough,
    );
    expect(styleOf(tester, edited, 'one')?.fontWeight, FontWeight.w600);
    expect(find.byKey(const ValueKey('history_current')), findsOneWidget);
    expect(find.byKey(const ValueKey('history_0')), findsOneWidget);
  });

  testWidgets('removed words are struck through, added words are bold', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      view(history: mockup),
      size: const Size(400, 800),
    );
    final edited = find.byKey(const ValueKey('history_1'));
    final removed = styleOf(tester, edited, 'an hour.');
    expect(removed?.decoration, TextDecoration.lineThrough);
    final tokens = AppTokens.of(tester.element(edited));
    expect(removed?.backgroundColor, tokens.red.withValues(alpha: .22));
    final added = styleOf(tester, edited, '20 minutes.');
    expect(added?.fontWeight, FontWeight.w600);
    expect(added?.backgroundColor, tokens.ok.withValues(alpha: .25));
  });

  testWidgets('the screen reader hears removed and added words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(
      tester,
      view(history: mockup),
      size: const Size(400, 800),
    );
    final semantics = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byKey(const ValueKey('history_1')),
            matching: find.byType(Semantics),
          ),
        )
        .map((s) => s.properties.label)
        .whereType<String>();
    expect(
      semantics.any(
        (label) =>
            label.contains('Removed: an hour.') &&
            label.contains('Added: 20 minutes.'),
      ),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('hostile text is cleaned and bounded', (tester) async {
    final hostile = EditHistory(
      original: version(r'$o', 1, 'invoice\u202Efdp.exe'),
      edits: [version(r'$a', 2, 'new\n\n\n${'́' * 300}${'x' * 40}')],
    );
    await pumpGoldenWidget(
      tester,
      view(history: hostile),
      size: const Size(400, 800),
    );
    final rlo = String.fromCharCode(0x202E);
    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(widget.text.toPlainText(), isNot(contains(rlo)));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions appear only when offered', (tester) async {
    await pumpGoldenWidget(
      tester,
      view(history: mockup),
      size: const Size(400, 800),
    );
    expect(find.byKey(const ValueKey('history_edit_again')), findsNothing);
    expect(find.byKey(const ValueKey('history_delete')), findsNothing);
    var edited = 0;
    var deleted = 0;
    await pumpGoldenWidget(
      tester,
      view(
        history: mockup,
        onEditAgain: () => edited++,
        onDelete: () => deleted++,
      ),
      size: const Size(400, 800),
    );
    await tester.tap(find.byKey(const ValueKey('history_edit_again')));
    await tester.tap(find.byKey(const ValueKey('history_delete')));
    expect((edited, deleted), (1, 1));
    expect(find.text('Edit again'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);
  });

  testWidgets('close is at least 44 px and works', (tester) async {
    var closed = 0;
    await pumpGoldenWidget(
      tester,
      view(history: mockup, onClose: () => closed++),
      size: const Size(400, 800),
    );
    final size = tester.getSize(
      find.byKey(const ValueKey('edit_history_close')),
    );
    expect(size.width, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const ValueKey('edit_history_close')));
    expect(closed, 1);
  });

  testWidgets('without any usable edit only the original is shown', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      view(
        history: EditHistory(
          original: version(r'$o', 1, 'only version'),
          edits: const [],
        ),
      ),
      size: const Size(400, 400),
    );
    expect(find.byKey(const ValueKey('history_current')), findsNothing);
    expect(find.byKey(const ValueKey('history_0')), findsOneWidget);
    expect(find.text('only version'), findsOneWidget);
    expect(find.text('No earlier versions are available.'), findsOneWidget);
  });

  testWidgets('empty and loading states', (tester) async {
    await pumpGoldenWidget(tester, view(), size: const Size(400, 400));
    expect(find.text('No earlier versions are available.'), findsOneWidget);
    await pumpGoldenWidget(
      tester,
      view(loading: true),
      size: const Size(400, 400),
      settle: false,
    );
    expect(find.text('Loading earlier versions…'), findsOneWidget);
    expect(find.text('No earlier versions are available.'), findsNothing);
  });

  testWidgets('fifty versions scroll without overflowing', (tester) async {
    final many = EditHistory(
      original: version(r'$o', 0, 'start'),
      edits: [
        for (var i = 1; i <= 50; i++) version('\$e$i', i % 60, 'version $i'),
      ],
    );
    await pumpGoldenWidget(
      tester,
      view(history: many),
      size: const Size(400, 500),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('goldens', (tester) async {
    await expectGoldenVariants(
      tester,
      'edit_history_sheet',
      Align(
        alignment: Alignment.bottomCenter,
        child: view(history: mockup, onEditAgain: () {}, onDelete: () {}),
      ),
      size: const Size(400, 760),
    );
  });
}
