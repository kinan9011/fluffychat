// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/pages/chat/events/html_message.dart';
import 'package:odango/utils/html_limits.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

Widget htmlWidget(Room room, String html) => Padding(
  padding: const EdgeInsets.all(8),
  child: HtmlMessage(
    html: html,
    room: room,
    fontSize: 15,
    linkStyle: const TextStyle(decoration: TextDecoration.underline),
    onOpen: (_) {},
  ),
);

void main() {
  late Room room;

  setUpAll(() async {
    final client = await prepareTestClient();
    room = Room(id: '!room:example.org', client: client);
  });

  group('capHtmlInput (W13 audit B-1)', () {
    test('keeps what a client can send, drops what it cannot', () {
      const limit = RichLimits.maxRenderInputUnits;
      expect(capHtmlInput('a' * limit), isNotNull);
      expect(capHtmlInput('a' * (limit + 1)), isNull);
      expect(capHtmlInput(null), isNull);
      expect(capHtmlInput(''), '');
    });
  });

  group('hostile nesting', () {
    testWidgets('9000 nested <div> neither overflows the stack nor throws', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        htmlWidget(room, '${'<div>' * 9000}deep${'</div>' * 9000}'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('thousands of nested lists render without an exception', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        htmlWidget(room, '${'<ul><li>'.padRight(40, ' ') * 3000}x'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('task list item without a child (B-3)', () {
    testWidgets('renders instead of throwing', (tester) async {
      await pumpGoldenWidget(
        tester,
        htmlWidget(room, '<ul><li class="task-list-item">text only</li></ul>'),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('text only', findRichText: true), findsOne);
    });
  });

  group('link spoofing (B-2)', () {
    Future<void> tapLink(WidgetTester tester, String html) async {
      await pumpGoldenWidget(tester, htmlWidget(room, html));
      await tester.tap(
        find
            .ancestor(
              of: find.textContaining('bank.com', findRichText: true),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'transparent parts that complete the address force the dialog',
      (tester) async {
        await tapLink(
          tester,
          '<a href="https://bank.com.evil.example/">'
          '<span data-mx-color="#00000000">https://</span>bank.com'
          '<span data-mx-color="#00000000">.evil.example/</span></a>',
        );
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets('a link whose text differs from the address asks first', (
      tester,
    ) async {
      await tapLink(
        tester,
        '<a href="https://evil.example/">bank.com login</a>',
      );
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('colours', () {
    testWidgets('an alpha channel or short hex is not a colour', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        htmlWidget(
          room,
          '<span data-mx-color="#00000000">alpha</span>'
          '<span data-mx-color="#f00">short</span>'
          '<span data-mx-color="#ff0000">plain</span>',
        ),
      );
      TextStyle? styleOfText(String text) {
        TextStyle? found;
        void walk(InlineSpan span, TextStyle? inherited) {
          if (span is! TextSpan) return;
          final style = inherited == null
              ? span.style
              : inherited.merge(span.style);
          if (span.text == text) found = style;
          for (final child in span.children ?? const <InlineSpan>[]) {
            walk(child, style);
          }
        }

        for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
          walk(rich.text, null);
        }
        return found;
      }

      expect(styleOfText('alpha')?.color, isNot(const Color(0x00000000)));
      expect(styleOfText('short')?.color, isNot(const Color(0xFFFF0000)));
      expect(styleOfText('plain')?.color, const Color(0xFFFF0000));
    });
  });
}
