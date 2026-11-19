// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/pages/chat/events/html_message.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

Widget htmlWidget(Room room, String html, {Color color = Colors.black}) =>
    Padding(
      padding: const EdgeInsets.all(8),
      child: HtmlMessage(
        html: html,
        room: room,
        fontSize: 15,
        linkStyle: const TextStyle(decoration: TextDecoration.underline),
        textColor: color,
        onOpen: (_) {},
      ),
    );

TextStyle? styleOf(WidgetTester tester, String text) {
  TextStyle? found;
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = inherited == null ? span.style : inherited.merge(span.style);
    if (span.text == text) found = style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, style);
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(richText.text, null);
  }
  return found;
}

void main() {
  late Room room;

  setUpAll(() async {
    final client = await prepareTestClient();
    room = Room(id: '!room:example.org', client: client);
  });

  testWidgets('maths renders its attribute in mono, not its children', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      htmlWidget(room, 'a <span data-mx-maths="x^2"><b>children</b></span> b'),
    );
    expect(styleOf(tester, 'x^2')?.fontFamily, AppTypography.monoFamily);
    expect(find.textContaining('children', findRichText: true), findsNothing);
  });

  testWidgets('block maths is a scrollable mono chip with a label', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      htmlWidget(
        room,
        '<div data-mx-maths="\\sum_i x_i"><pre><code>fallback</code></pre></div>',
      ),
    );
    expect(find.text('\\sum_i x_i'), findsOneWidget);
    expect(find.text('fallback', findRichText: true), findsNothing);
    expect(find.bySemanticsLabel('Formula'), findsOneWidget);
  });

  testWidgets('an obscured spoiler hides its text from semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(
      tester,
      htmlWidget(room, 'x <span data-mx-spoiler>SECRET-42</span>'),
    );
    expect(find.bySemanticsLabel(RegExp('Spoiler')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('SECRET')), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('Spoiler')));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Spoiler')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('SECRET')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an obscured spoiler is announced as the spoiler label only', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(
      tester,
      htmlWidget(room, 'x <span data-mx-spoiler>SECRET-42</span>'),
    );
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Spoiler')));
    expect(node.label, 'x \nSpoiler');
    handle.dispose();
  });

  for (final (name, html, secret) in [
    (
      'inline code',
      '<span data-mx-spoiler>a <code>SECRET-CODE</code> b</span>',
      'SECRET-CODE',
    ),
    (
      'inline maths',
      '<span data-mx-spoiler><span data-mx-maths="SECRET-TEX">x</span></span>',
      'SECRET-TEX',
    ),
    (
      'block maths',
      '<span data-mx-spoiler><div data-mx-maths="SECRET-BLOCK">x</div></span>',
      'SECRET-BLOCK',
    ),
    (
      'maths on the spoiler element itself',
      '<span data-mx-spoiler data-mx-maths="SECRET-SAME">x</span>',
      'SECRET-SAME',
    ),
    (
      'fenced block',
      '<span data-mx-spoiler><pre><code>SECRET-FENCE</code></pre></span>',
      'SECRET-FENCE',
    ),
  ]) {
    testWidgets('an obscured spoiler builds no $name until tapped', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpGoldenWidget(
        tester,
        SelectionArea(child: htmlWidget(room, html)),
      );
      expect(find.textContaining(secret, findRichText: true), findsNothing);
      expect(find.bySemanticsLabel(RegExp(secret)), findsNothing);
      await tester.tap(find.bySemanticsLabel(RegExp('Spoiler')));
      await tester.pump();
      expect(find.textContaining(secret, findRichText: true), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('headings, underline and strike keep their styles', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      htmlWidget(room, '<h1>one</h1><h6>six</h6><u>under</u> <del>gone</del>'),
      size: const Size(400, 600),
    );
    expect(styleOf(tester, 'one')?.fontSize, 15 * 1.6);
    expect(styleOf(tester, 'six')?.fontSize, 15 * 1.1);
    expect(styleOf(tester, 'under')?.decoration, TextDecoration.underline);
    expect(styleOf(tester, 'gone')?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('a 5000 element message builds without exception', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      SingleChildScrollView(child: htmlWidget(room, '<i>x</i>' * 5000)),
    );
    expect(tester.takeException(), isNull);
  });
}
