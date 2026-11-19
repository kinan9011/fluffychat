// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/pages/chat/chat_wallpaper.dart';
import 'package:odango/pages/chat/events/deleted_bubble_content.dart';
import 'package:odango/pages/chat/events/file_bubble_view.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';
import 'package:odango/pages/chat/events/message_footer.dart';
import 'package:odango/pages/chat/events/poll.dart';
import 'package:odango/pages/chat/events/reaction_pills.dart';
import 'package:odango/pages/chat/events/reply_content.dart';
import 'package:odango/pages/chat/events/utd_bubble_content.dart';
import 'package:odango/pages/chat/events/voice_bubble_view.dart';
import 'package:odango/pages/chat/seen_by_row.dart';
import 'package:odango/utils/account_config.dart';
import 'package:odango/utils/chat/message_ticks.dart';
import 'package:odango/utils/chat/reaction_summary.dart';
import 'package:odango/utils/chat/waveform.dart';
import 'package:odango/utils/string_color.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient());

  Widget bubble({
    required Widget child,
    bool outgoing = false,
    bool tail = true,
    bool mention = false,
    BubbleKind kind = BubbleKind.normal,
  }) => Align(
    alignment: outgoing
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: MessageBubble(
      kind: kind,
      outgoing: outgoing,
      tail: tail,
      mention: mention,
      maxWidth: 300,
      child: child,
    ),
  );

  Widget text(
    BuildContext context,
    String body, {
    bool outgoing = false,
    String? sender,
    Widget? quote,
    String time = '12:41',
    bool edited = false,
    Tick tick = Tick.none,
    BubbleKind kind = BubbleKind.normal,
  }) {
    final colors = BubbleColors.of(
      AppTokens.of(context),
      outgoing: outgoing,
      kind: kind,
    );
    return BubbleBody(
      content: Padding(
        padding: const EdgeInsets.fromLTRB(13, 8, 13, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            if (sender != null)
              Text(
                sender,
                style: TextStyle(
                  color: '@kim:example.org'.nameColor(
                    Theme.of(context).brightness,
                  ),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ?quote,
            Text(body, style: TextStyle(color: colors.text, fontSize: 15.5)),
          ],
        ),
      ),
      footer: MessageFooter(
        time: time,
        edited: edited,
        tick: tick,
        color: colors.secondary,
      ),
    );
  }

  Widget gallery() => Builder(
    builder: (context) => Stack(
      children: [
        const Positioned.fill(
          child: ChatWallpaper(config: ApplicationAccountConfig()),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              bubble(
                tail: false,
                child: text(
                  context,
                  'Grouped, no tail, with a sender name',
                  sender: 'Kim',
                ),
              ),
              bubble(
                mention: true,
                child: text(
                  context,
                  '@Anna can you check the build before lunch?',
                  sender: 'Kim',
                ),
              ),
              bubble(
                child: text(
                  context,
                  'Mara and Jonas both asked: a long message wraps over '
                  'several lines inside the bubble.',
                ),
              ),
              bubble(
                outgoing: true,
                child: text(
                  context,
                  'Testing it now',
                  outgoing: true,
                  edited: true,
                  tick: Tick.seen,
                  time: '12:44',
                ),
              ),
              bubble(
                outgoing: true,
                child: text(
                  context,
                  'Delivered',
                  outgoing: true,
                  tick: Tick.sent,
                ),
              ),
              bubble(
                outgoing: true,
                child: text(
                  context,
                  'Sending...',
                  outgoing: true,
                  tick: Tick.sending,
                ),
              ),
              bubble(
                outgoing: true,
                kind: BubbleKind.error,
                child: text(
                  context,
                  'Could not be sent',
                  outgoing: true,
                  tick: Tick.error,
                  kind: BubbleKind.error,
                ),
              ),
              bubble(
                child: text(
                  context,
                  'Yes, both.',
                  quote: const ReplyQuoteView(
                    name: 'Mara',
                    text: 'Did you get the CV files?',
                    outgoing: false,
                  ),
                ),
              ),
              bubble(
                outgoing: true,
                child: text(
                  context,
                  'Sending the final versions back.',
                  outgoing: true,
                  tick: Tick.seen,
                  quote: const ReplyQuoteView(
                    name: 'Mara',
                    text: 'Did you get the CV files?',
                    outgoing: true,
                  ),
                ),
              ),
              bubble(
                child: const DeletedBubbleContent(
                  text: 'Jonas deleted this message',
                ),
              ),
              bubble(
                kind: BubbleKind.undecryptable,
                child: UtdBubbleContent(onWhy: () {}),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ReactionPills(
                  client: client,
                  alignEnd: false,
                  summary: ReactionSummary([
                    ReactionEntry('👍')
                      ..count = 3
                      ..own = true,
                    ReactionEntry('🎉')..count = 1,
                    ReactionEntry('mxc://example.org/abc')..count = 2,
                  ], 6),
                ),
              ),
              SeenByView(
                client: client,
                alignEnd: true,
                users: const [
                  SeenUser(id: '@mara:example.org', name: 'Mara'),
                  SeenUser(id: '@jonas:example.org', name: 'Jonas'),
                  SeenUser(id: '@kim:example.org', name: 'Kim'),
                  SeenUser(id: '@lena:example.org', name: 'Lena'),
                ],
              ),
              bubble(
                child: VoiceBubbleView(
                  playing: false,
                  progress: 0.4,
                  bars: resampleWaveform(
                    List.generate(100, (i) => (i * 37) % 1024),
                  ),
                  duration: '0:14',
                  outgoing: false,
                ),
              ),
              bubble(
                outgoing: true,
                child: VoiceBubbleView(
                  playing: true,
                  progress: 0.7,
                  bars: resampleWaveform(
                    List.generate(100, (i) => (i * 53) % 1024),
                  ),
                  duration: '0:09',
                  outgoing: true,
                ),
              ),
              bubble(
                outgoing: true,
                child: const FileBubbleView(
                  filename: 'cv-final-version-for-the-agency.odt',
                  meta: '184 KB · ODT',
                  outgoing: true,
                ),
              ),
              bubble(
                child: const FileBubbleView(
                  filename: 'notes.pdf',
                  meta: '2.1 MB · PDF',
                  outgoing: false,
                ),
              ),
              bubble(
                child: PollView(
                  client: client,
                  question: 'When do we ship 2.0?',
                  options: const [
                    PollOptionView(
                      id: 'a',
                      text: 'Friday',
                      selected: true,
                      voters: [
                        PollVoter(id: '@a:x', name: 'A'),
                        PollVoter(id: '@b:x', name: 'B'),
                      ],
                    ),
                    PollOptionView(
                      id: 'b',
                      text: 'Next week',
                      selected: false,
                      voters: [PollVoter(id: '@c:x', name: 'C')],
                    ),
                  ],
                  totalVoters: 3,
                  answersVisible: true,
                  canVote: true,
                  ended: false,
                  canEnd: false,
                  outgoing: false,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  for (final variant in goldenVariants) {
    testWidgets('bubble gallery ${variant.suffix}', (tester) async {
      await pumpGoldenWidget(
        tester,
        TickerMode(enabled: false, child: gallery()),
        brightness: variant.brightness,
        rtl: variant.rtl,
        size: const Size(400, 1900),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubbles_${variant.suffix}.png'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }
}
