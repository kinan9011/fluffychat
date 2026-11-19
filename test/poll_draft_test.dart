// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/polls/poll_content.dart';

PollDraft draft({
  String question = 'Question?',
  List<String> answers = const ['Yes', 'No'],
  bool multiple = false,
  bool hideResults = false,
  bool quiz = false,
  Set<int> correct = const {},
}) => PollDraft(
  question: question,
  answers: answers,
  multiple: multiple,
  hideResults: hideResults,
  quiz: quiz,
  correct: correct,
);

void main() {
  test('a plain draft is valid', () => expect(draft().validate(), isNull));

  test('each error', () {
    expect(draft(question: '  ').validate(), PollDraftError.emptyQuestion);
    expect(
      draft(question: 'q' * 256).validate(),
      PollDraftError.questionTooLong,
    );
    expect(draft(question: 'q' * 255).validate(), isNull);
    expect(draft(answers: ['one']).validate(), PollDraftError.tooFewAnswers);
    expect(
      draft(answers: [for (var i = 0; i < 11; i++) 'a$i']).validate(),
      PollDraftError.tooManyAnswers,
    );
    expect(
      draft(answers: [for (var i = 0; i < 10; i++) 'a$i']).validate(),
      isNull,
    );
    expect(draft(answers: ['a', ' ']).validate(), PollDraftError.emptyAnswer);
    expect(
      draft(answers: ['a', 'b' * 101]).validate(),
      PollDraftError.answerTooLong,
    );
    expect(draft(answers: ['a', 'b' * 100]).validate(), isNull);
    expect(
      draft(answers: ['Yes', ' yes ']).validate(),
      PollDraftError.duplicateAnswer,
    );
    expect(
      draft(quiz: true, multiple: true, correct: {0}).validate(),
      PollDraftError.quizWithMultiple,
    );
    expect(draft(quiz: true).validate(), PollDraftError.quizNeedsCorrect);
    expect(
      draft(quiz: true, correct: {0, 1}).validate(),
      PollDraftError.quizNeedsCorrect,
    );
    expect(
      draft(quiz: true, correct: {5}).validate(),
      PollDraftError.quizNeedsCorrect,
    );
    expect(draft(quiz: true, correct: {1}).validate(), isNull);
  });

  test('graphemes, not code units, are counted at the boundary', () {
    expect(draft(question: '👩‍👩‍👧‍👦' * 255).validate(), isNull);
    expect(
      draft(question: '👩‍👩‍👧‍👦' * 256).validate(),
      PollDraftError.questionTooLong,
    );
  });

  test('control characters and whitespace are normalised', () {
    final d = draft(question: ' a\u0000\n b ', answers: ['x\ty', 'z']);
    expect(d.question, 'a b');
    expect(d.answers, ['x y', 'z']);
  });

  group('content', () {
    Map<String, Object?> start(Map<String, Object?> content) =>
        content['org.matrix.msc3381.poll.start']! as Map<String, Object?>;

    test('a plain poll', () {
      final content = draft().toStartContent();
      expect(content['org.matrix.msc1767.text'], 'Question?\n1. Yes\n2. No');
      final s = start(content);
      expect(s['kind'], 'org.matrix.msc3381.poll.disclosed');
      expect(s['max_selections'], 1);
      expect((s['answers']! as List).map((a) => (a as Map)['id']), ['1', '2']);
      expect(content.containsKey(pollQuizKey), isFalse);
    });

    test('multiple answers allow all of them', () {
      expect(
        start(
          draft(answers: ['a', 'b', 'c'], multiple: true).toStartContent(),
        )['max_selections'],
        3,
      );
    });

    test('hide results is the undisclosed kind', () {
      expect(
        start(draft(hideResults: true).toStartContent())['kind'],
        'org.matrix.msc3381.poll.undisclosed',
      );
    });

    test('a quiz carries the correct answer id', () {
      final content = draft(quiz: true, correct: {1}).toStartContent();
      expect(content[pollQuizKey], {
        'correct_answer_ids': ['2'],
      });
    });

    test('the fallback body is capped', () {
      final content = draft(
        question: 'q' * 255,
        answers: [for (var i = 0; i < 10; i++) 'a' * 100],
      ).toStartContent();
      expect(
        (content['org.matrix.msc1767.text']! as String).length,
        lessThanOrEqualTo(PollLimits.bodyMax),
      );
    });

    test('the cap never leaves half an emoji behind', () {
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';
      const smile = '\u{1F600}';
      for (var lead = 1; lead < 24; lead++) {
        final full =
            draft(
                  question: 'q' * lead,
                  answers: [
                    for (var i = 0; i < 10; i++)
                      (i.isEven ? family : smile) * 100,
                  ],
                ).toStartContent()['org.matrix.msc1767.text']!
                as String;
        expect(full.length, lessThanOrEqualTo(PollLimits.bodyMax));
        final lone = full.runes.any((r) => r >= 0xD800 && r <= 0xDFFF);
        expect(lone, isFalse, reason: 'lead $lead');
        final whole = [
          'q' * lead,
          for (var i = 0; i < 10; i++)
            '${i + 1}. ${(i.isEven ? family : smile) * 100}',
        ].join('\n');
        expect(
          whole.characters.take(full.characters.length).toString(),
          full,
          reason: 'lead $lead: a prefix made of whole clusters',
        );
      }
    });

    test('what is sent parses back to the same poll', () {
      final parsed = PollContent.parse(
        draft(quiz: true, correct: {0}, hideResults: true).toStartContent(),
      )!;
      expect(parsed.question, 'Question?');
      expect(parsed.undisclosed, isTrue);
      expect(parsed.quizCorrectIds, {'1'});
      expect(parsed.answers.map((a) => a.text), ['Yes', 'No']);
    });
  });
}
