// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/events/poll.dart';
import 'package:fluffychat/pages/chat/poll_composer/poll_composer.dart';
import 'package:fluffychat/utils/polls/poll_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/golden.dart';
import 'utils/recording_api.dart';
import 'utils/test_client.dart';

PollView view({
  bool quiz = true,
  List<PollQuizMark> marks = const [
    PollQuizMark.none,
    PollQuizMark.none,
    PollQuizMark.none,
  ],
  int selected = -1,
  bool answersVisible = true,
  bool outgoing = false,
}) => PollView(
  question: 'Which protocol does FluffyChat use?',
  quiz: quiz,
  options: [
    for (var i = 0; i < 3; i++)
      PollOptionView(
        id: '${i + 1}',
        text: ['Matrix', 'XMPP', 'IRC'][i],
        selected: i == selected,
        voters: const [],
        mark: marks[i],
      ),
  ],
  totalVoters: 2,
  answersVisible: answersVisible,
  canVote: true,
  ended: false,
  canEnd: false,
  outgoing: outgoing,
);

void main() {
  Future<void> pump(WidgetTester tester, PollView poll) =>
      pumpGoldenWidget(tester, Center(child: poll), size: const Size(400, 300));

  testWidgets('a quiz that was not answered shows no marks', (tester) async {
    await pump(tester, view());
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.byIcon(Icons.cancel_rounded), findsNothing);
    expect(find.text('Quiz'), findsOneWidget);
  });

  testWidgets('a normal poll has no quiz badge', (tester) async {
    await pump(tester, view(quiz: false));
    expect(find.text('Quiz'), findsNothing);
  });

  testWidgets('a right answer is marked with an icon and a label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      view(
        selected: 0,
        marks: [PollQuizMark.correct, PollQuizMark.none, PollQuizMark.none],
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsNothing);
    expect(find.bySemanticsLabel('Matrix, Correct answer'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a wrong answer is marked and the right one is shown', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      view(
        selected: 1,
        marks: [PollQuizMark.correct, PollQuizMark.wrong, PollQuizMark.none],
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(
      find.bySemanticsLabel('XMPP, Your answer was not correct'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Matrix, Correct answer'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('hidden results say so', (tester) async {
    await pump(tester, view(quiz: false, answersVisible: false));
    expect(
      find.textContaining('visible when poll has ended', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('every option row is at least 44 px high', (tester) async {
    await pump(tester, view());
    for (final inkWell in find.byType(InkWell).evaluate()) {
      expect(inkWell.size!.height, greaterThanOrEqualTo(44));
    }
  });

  group('a malformed poll event', () {
    late Client client;

    setUpAll(() async => client = await prepareTestClient());
    tearDownAll(() => client.dispose(closeDatabase: true));

    testWidgets('shows a short notice and no options', (tester) async {
      final room = client.rooms.firstWhere(
        (r) => r.membership == Membership.join,
      );
      final timeline = await tester.runAsync(room.getTimeline);
      final event = Event(
        type: PollEventContent.startType,
        content: {
          PollEventContent.startType: {'question': 5, 'answers': 'x'},
        },
        room: room,
        eventId: r'$bad:example.org',
        senderId: '@bob:example.org',
        originServerTs: DateTime.now(),
      );
      await pumpGoldenWidget(
        tester,
        PollWidget(event: event, timeline: timeline!),
      );
      expect(find.text("This poll can't be shown"), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('voting in a quiz', () {
    late RecordingApi api;
    late Client client;
    late Room room;
    late Timeline timeline;

    setUp(() async {
      api = RecordingApi();
      client = await prepareTestClient(httpClient: api);
      room = client.getRoomById('!calls:example.com')!;
      timeline = await room.getTimeline();
    });
    tearDown(() => client.dispose(closeDatabase: true));

    Event pollEvent({required bool quiz, bool multiple = false}) => Event(
      type: PollEventContent.startType,
      content: PollDraft(
        question: 'Which one?',
        answers: const ['Matrix', 'XMPP', 'IRC'],
        multiple: multiple,
        hideResults: false,
        quiz: quiz,
        correct: quiz ? const {0} : const {},
      ).toStartContent(),
      room: room,
      eventId: r'$poll:example.org',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now().subtract(const Duration(minutes: 5)),
    );

    void vote(Event poll, String id) =>
        ((timeline.aggregatedEvents[poll.eventId] ??=
                    {})[RelationshipTypes.reference] ??=
                {})
            .add(
              Event(
                type: PollEventContent.responseType,
                content: {
                  PollEventContent.responseType: {
                    'answers': [id],
                  },
                  'm.relates_to': {
                    'rel_type': RelationshipTypes.reference,
                    'event_id': poll.eventId,
                  },
                },
                room: room,
                eventId: r'$vote:example.org',
                senderId: client.userID!,
                originServerTs: DateTime.now(),
              ),
            );

    Future<void> tapOption(WidgetTester tester, String text) async {
      await tester.tap(find.text(text), warnIfMissed: false);
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    int votesSent() => api.requests('/send/', method: 'PUT').length;

    testWidgets('the first vote is sent', (tester) async {
      final poll = pollEvent(quiz: true);
      await pumpGoldenWidget(
        tester,
        PollWidget(event: poll, timeline: timeline),
      );
      api.clear();
      await tapOption(tester, 'XMPP');
      expect(votesSent(), 1);
    });

    testWidgets('after the first vote a quiz answer cannot be changed', (
      tester,
    ) async {
      final poll = pollEvent(quiz: true);
      vote(poll, '2');
      await pumpGoldenWidget(
        tester,
        PollWidget(event: poll, timeline: timeline),
      );
      api.clear();
      await tapOption(tester, 'Matrix');
      await tapOption(tester, 'XMPP');
      expect(votesSent(), 0);
    });

    testWidgets('an ordinary poll can still be changed after voting', (
      tester,
    ) async {
      final poll = pollEvent(quiz: false);
      vote(poll, '2');
      await pumpGoldenWidget(
        tester,
        PollWidget(event: poll, timeline: timeline),
      );
      api.clear();
      await tapOption(tester, 'Matrix');
      expect(votesSent(), 1);
    });
  });

  group('goldens', () {
    testGoldens('PollView quiz', (tester) async {
      for (final variant in goldenVariants) {
        await pumpGoldenWidget(
          tester,
          Center(
            child: view(
              selected: 1,
              marks: [
                PollQuizMark.correct,
                PollQuizMark.wrong,
                PollQuizMark.none,
              ],
            ),
          ),
          brightness: variant.brightness,
          rtl: variant.rtl,
          locale: variant.locale,
          size: const Size(400, 300),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/poll_view_quiz_${variant.suffix}.png'),
        );
      }
    });

    testGoldens('PollComposer', (tester) async {
      final client = (await tester.runAsync(prepareTestClient))!;
      final room = client.rooms.firstWhere(
        (r) => r.membership == Membership.join,
      );
      for (final variant in goldenVariants) {
        await pumpGoldenWidget(
          tester,
          PollComposer(key: ValueKey(variant.suffix), room: room),
          brightness: variant.brightness,
          rtl: variant.rtl,
          locale: variant.locale,
          size: const Size(400, 900),
        );
        final c = tester.state<PollComposerController>(
          find.byType(PollComposer),
        );
        c.question.text = 'Which protocol does FluffyChat use?';
        c.answers[0].text.text = 'Matrix';
        c.answers[1].text.text = 'XMPP';
        c.addAnswer();
        c.answers[2].text.text = 'IRC';
        c.toggleQuiz(true);
        c.markCorrect(c.answers[0]);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/poll_composer_${variant.suffix}.png'),
        );
      }
      await tester.runAsync(() => client.dispose(closeDatabase: true));
    });
  });
}
