// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/pages/chat/events/html_message.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

final _doc = RichDocument([
  const Block(BlockKind.heading, [TextRun('Release 2.1')], level: 2),
  Block(BlockKind.paragraph, [
    const TextRun('Notes are '),
    const TextRun('final', marks: {InlineMark.bold}),
    const TextRun(', '),
    const TextRun('tested', marks: {InlineMark.italic}),
    const TextRun(', '),
    const TextRun('signed', marks: {InlineMark.underline}),
    const TextRun(', '),
    const TextRun('dropped', marks: {InlineMark.strike}),
    const TextRun(' and '),
    const TextRun('flutter', marks: {InlineMark.code}),
    const TextRun(': '),
    TextRun('changelog', link: Uri.parse('https://example.org/changelog')),
  ]),
  Block(BlockKind.paragraph, [
    const TextRun('Codename: '),
    const TextRun('Marshmallow', marks: {InlineMark.spoiler}),
  ]),
  const Block(BlockKind.bullet, [TextRun('Spaces as tabs')]),
  const Block(BlockKind.bullet, [TextRun('Scheduled sending')]),
  const Block(BlockKind.ordered, [TextRun('Tag the release')]),
  const Block(BlockKind.ordered, [TextRun('Publish')]),
  const Block(BlockKind.checklist, [
    TextRun('Push notifications'),
  ], checked: true),
  const Block(BlockKind.checklist, [TextRun('Tablet layout')]),
  const Block(BlockKind.quote, [TextRun('Ship it when the list is green.')]),
  const Block(BlockKind.codeBlock, [
    TextRun('git tag v2.1.0\ngit push --tags'),
  ], language: 'bash'),
  Block(BlockKind.paragraph, const [
    TextRun('Energy '),
    MathsInline('E = mc^2'),
  ]),
  const Block(BlockKind.mathsBlock, [TextRun(r'\sum_{i=1}^n i')]),
]);

void main() {
  late Room room;
  late String html;

  setUpAll(() async {
    final client = await prepareTestClient();
    room = Room(id: '!room:example.org', client: client);
    html = RichHtmlSerializer.serialize(_doc).formattedBody;
  });

  Widget bubble(AppTokens tokens, {required bool outgoing}) => MessageBubble(
    kind: BubbleKind.normal,
    outgoing: outgoing,
    tail: true,
    child: SizedBox(
      width: 300,
      child: HtmlMessage(
        html: html,
        room: room,
        fontSize: 15,
        textColor: outgoing ? tokens.outFg : tokens.fg,
        linkStyle: TextStyle(
          color: outgoing ? tokens.outFg : tokens.acc,
          decoration: TextDecoration.underline,
        ),
        onOpen: (_) {},
      ),
    ),
  );

  for (final variant in goldenVariants.where((v) => !v.rtl)) {
    testWidgets('rich message bubbles ${variant.suffix}', (tester) async {
      await pumpGoldenWidget(
        tester,
        Builder(
          builder: (context) {
            final tokens = AppTokens.of(context);
            return ColoredBox(
              color: tokens.bg,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      bubble(tokens, outgoing: false),
                      Align(
                        alignment: Alignment.centerRight,
                        child: bubble(tokens, outgoing: true),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        brightness: variant.brightness,
        size: const Size(400, 1000),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rich_message_bubble_${variant.suffix}.png'),
      );
    });
  }
}
