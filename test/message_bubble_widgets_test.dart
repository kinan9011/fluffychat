// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/themes.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/events/file_bubble_view.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';
import 'package:odango/pages/chat/events/poll.dart';
import 'package:odango/pages/chat/events/reaction_bar.dart';
import 'package:odango/pages/chat/events/reaction_pills.dart';
import 'package:odango/pages/chat/events/voice_bubble_view.dart';
import 'package:odango/pages/chat/seen_by_row.dart';
import 'package:odango/utils/chat/reaction_summary.dart';
import 'package:odango/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  setUpAll(() async {
    client = await prepareTestClient();
    room = Room(id: '!r:example.org', client: client);
  });

  Event event({
    String type = EventTypes.Message,
    Map<String, Object?>? content,
    EventStatus status = EventStatus.synced,
    String sender = '@bob:example.org',
  }) => Event(
    type: type,
    content: content ?? {'msgtype': MessageTypes.Text, 'body': 'x'},
    room: room,
    eventId: r'$e:example.org',
    senderId: sender,
    originServerTs: DateTime(2030),
    status: status,
  );

  group('bubbleKind', () {
    test('plain message', () {
      expect(bubbleKind(event(), own: false), BubbleKind.normal);
    });

    test('redacted is deleted, also when it was undecryptable', () {
      final deleted = event()
        ..setRedactionEvent(event(type: EventTypes.Redaction, content: {}));
      expect(bubbleKind(deleted, own: false), BubbleKind.deleted);
      final deletedUtd = event(
        type: EventTypes.Encrypted,
        content: {'msgtype': MessageTypes.BadEncrypted},
      )..setRedactionEvent(event(type: EventTypes.Redaction, content: {}));
      expect(bubbleKind(deletedUtd, own: false), BubbleKind.deleted);
    });

    test('redacted by the server, content untouched, is still deleted '
        '(REV m8)', () {
      final server = Event(
        type: EventTypes.Encrypted,
        content: {'msgtype': MessageTypes.BadEncrypted},
        room: room,
        eventId: r'$u:example.org',
        senderId: '@bob:example.org',
        originServerTs: DateTime(2030),
        unsigned: {
          'redacted_because': {
            'type': EventTypes.Redaction,
            'content': <String, Object?>{},
            'event_id': r'$r:example.org',
            'sender': '@bob:example.org',
            'origin_server_ts': 1,
          },
        },
      );
      expect(server.redacted, isTrue);
      expect(bubbleKind(server, own: false), BubbleKind.deleted);
    });

    test('bad encrypted is undecryptable', () {
      final utd = event(
        type: EventTypes.Encrypted,
        content: {'msgtype': MessageTypes.BadEncrypted},
      );
      expect(bubbleKind(utd, own: false), BubbleKind.undecryptable);
    });

    test('a failed own message is an error, a failed foreign one is not', () {
      final failed = event(status: EventStatus.error);
      expect(bubbleKind(failed, own: true), BubbleKind.error);
      expect(bubbleKind(failed, own: false), BubbleKind.normal);
    });
  });

  test('undecryptable events are never folded into "more events"', () {
    final utd = event(
      type: EventTypes.Encrypted,
      content: {'msgtype': MessageTypes.BadEncrypted},
    );
    expect(utd.isCollapsedState, isFalse);
    expect(
      event(type: EventTypes.RoomName, content: {}).isCollapsedState,
      isTrue,
    );
  });

  group('MessageBubble', () {
    final tokens = AppTokens.light();
    MessageBubble bubble({
      BubbleKind kind = BubbleKind.normal,
      bool outgoing = false,
      bool mention = false,
    }) => MessageBubble(
      kind: kind,
      outgoing: outgoing,
      tail: true,
      mention: mention,
      child: const SizedBox(width: 10, height: 10),
    );

    test('ring colours', () {
      expect(bubble(mention: true).ringColor(tokens), tokens.acc);
      expect(bubble().ringColor(tokens), isNull);
      expect(
        bubble(kind: BubbleKind.undecryptable).ringColor(tokens),
        tokens.warn,
      );
    });

    test('an outgoing bubble never gets a mention ring', () {
      expect(bubble(outgoing: true, mention: true).ringColor(tokens), isNull);
    });

    testWidgets('fills: surf, outS and red for errors', (tester) async {
      Future<Color> fill(MessageBubble bubble) async {
        await pumpGoldenWidget(tester, Center(child: bubble));
        return tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byType(MessageBubble),
                matching: find.byType(ColoredBox),
              ),
            )
            .color;
      }

      final t = AppTokens.light();
      expect(await fill(bubble()), t.surf);
      expect(await fill(bubble(outgoing: true)), t.outS);
      expect(await fill(bubble(outgoing: true, kind: BubbleKind.error)), t.red);
    });
  });

  group('PollView', () {
    PollView poll({
      int options = 2,
      bool visible = true,
      bool ended = false,
      bool canEnd = false,
      void Function(String)? onVote,
    }) => PollView(
      client: client,
      question: 'When?',
      options: [
        for (var i = 0; i < options; i++)
          PollOptionView(
            id: 'o$i',
            text: 'Option $i',
            selected: i == 0,
            voters: [if (i == 0) const PollVoter(id: '@a:x', name: 'A')],
          ),
      ],
      totalVoters: 1,
      answersVisible: visible,
      canVote: true,
      ended: ended,
      canEnd: canEnd,
      outgoing: false,
      onVote: onVote,
    );

    testWidgets('at most 20 options are drawn', (tester) async {
      await pumpGoldenWidget(
        tester,
        SingleChildScrollView(child: poll(options: 25)),
        size: const Size(400, 2400),
      );
      expect(find.textContaining('Option '), findsNWidgets(20));
      expect(find.text('Option 20'), findsNothing);
    });

    testWidgets('percentages, vote count and selection', (tester) async {
      await pumpGoldenWidget(tester, poll());
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('One vote'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('hidden results hide percentages', (tester) async {
      await pumpGoldenWidget(tester, poll(visible: false));
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('visible when'), findsOneWidget);
    });

    testWidgets('tapping an option votes', (tester) async {
      String? voted;
      await pumpGoldenWidget(tester, poll(onVote: (id) => voted = id));
      await tester.tap(find.text('Option 1'));
      expect(voted, 'o1');
    });

    testWidgets('an ended poll says so', (tester) async {
      await pumpGoldenWidget(tester, poll(ended: true));
      expect(find.textContaining('ended'), findsOneWidget);
    });
  });

  group('SeenByView', () {
    SeenUser user(int i, {String? name}) =>
        SeenUser(id: '@u$i:x', name: name ?? 'User$i');

    testWidgets('nobody, nothing', (tester) async {
      await pumpGoldenWidget(
        tester,
        const SeenByView(users: [], alignEnd: true),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('one or two names are listed in full', (tester) async {
      await pumpGoldenWidget(
        tester,
        SeenByView(client: client, users: [user(1), user(2)], alignEnd: true),
      );
      expect(find.text('Seen by User1, User2'), findsOneWidget);
    });

    testWidgets('more than two: two names and +N, at most 3 avatars', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        SeenByView(
          client: client,
          users: [for (var i = 1; i <= 6; i++) user(i)],
          alignEnd: true,
        ),
      );
      expect(find.text('Seen by User1, User2 +4'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SeenByView),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'Avatar',
          ),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('names carry no bidi override or line break (SEC L4)', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        SeenByView(
          client: client,
          users: const [
            SeenUser(id: '@a:example.org', name: 'Mara\u202E\nevil'),
          ],
          alignEnd: true,
        ),
      );
      expect(find.text('Seen by Mara evil'), findsOneWidget);
    });

    testWidgets('a hostile name stays on one line', (tester) async {
      await pumpGoldenWidget(
        tester,
        SeenByView(
          client: client,
          users: [user(1, name: 'W' * 5000)],
          alignEnd: false,
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.textContaining('Seen by'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('ReactionPills', () {
    testWidgets('tap targets are 44 px and taps arrive', (tester) async {
      final taps = <String>[];
      await pumpGoldenWidget(
        tester,
        ReactionPills(
          client: client,
          alignEnd: false,
          summary: ReactionSummary([
            ReactionEntry('👍')
              ..count = 2
              ..own = true,
          ], 0),
          onTap: (entry) => taps.add(entry.key),
        ),
      );
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(ReactionPills),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
      final chip = tester.getSize(
        find.byKey(const ValueKey('reaction_chip_👍')),
      );
      expect(chip.height, 28, reason: 'the chip is smaller than its hit box');
      await tester.tap(find.text('2'));
      expect(taps, ['👍']);
    });

    testWidgets('the semantics label carries the count and the state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpGoldenWidget(
        tester,
        ReactionPills(
          client: client,
          alignEnd: false,
          summary: ReactionSummary([
            ReactionEntry('🎉')
              ..count = 3
              ..own = true,
          ], 0),
          onTap: (_) {},
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('🎉, 3'));
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('a pill exposes tap and long press to screen readers and a '
        'custom emoji is named (REV m6)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGoldenWidget(tester, const SizedBox());
      await tester.pumpWidget(
        Builder(
          builder: (context) => MaterialApp(
            theme: FluffyThemes.buildTheme(context, Brightness.light),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: ReactionPills(
                client: client,
                alignEnd: false,
                summary: ReactionSummary([
                  ReactionEntry('mxc://example.org/abc')..count = 2,
                ], 0),
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Custom reaction, 2'),
      );
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('the quick reactions can be activated by a screen reader '
        '(REV m6)', (tester) async {
      final handle = tester.ensureSemantics();
      final sent = <String>[];
      await pumpGoldenWidget(
        tester,
        Center(
          child: ReactionBar(
            room: room,
            sentReactions: const {},
            onReact: sent.add,
          ),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('👍'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('hidden keys show as a plain +N', (tester) async {
      await pumpGoldenWidget(
        tester,
        ReactionPills(
          client: client,
          alignEnd: false,
          summary: ReactionSummary([ReactionEntry('👍')..count = 1], 6),
        ),
      );
      expect(find.text('+6'), findsOneWidget);
    });
  });

  group('voice and file bubbles', () {
    testWidgets('voice: the play button reflects the state', (tester) async {
      Future<void> pumpVoice({required bool playing}) => pumpGoldenWidget(
        tester,
        VoiceBubbleView(
          playing: playing,
          progress: 0.5,
          bars: List.filled(26, 0.5),
          duration: '0:14',
          outgoing: false,
          onPlayPause: () {},
        ),
      );
      await pumpVoice(playing: false);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await pumpVoice(playing: true);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.text('0:14'), findsOneWidget);
    });

    testWidgets('file: a hostile name stays on one line', (tester) async {
      await pumpGoldenWidget(
        tester,
        FileBubbleView(
          filename: '${'x' * 4000}.pdf',
          meta: '1 KB · PDF',
          outgoing: true,
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.textContaining('xxxx'));
      expect(text.maxLines, 1);
    });
  });
}
