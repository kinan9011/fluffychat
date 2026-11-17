// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/utils/polls/poll_content.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

Map<String, Object?> poll({
  Object? question = 'Which one?',
  Object? answers,
  Object? maxSelections = 1,
  Object? kind = 'org.matrix.msc3381.poll.disclosed',
  Object? quiz,
}) => {
  'org.matrix.msc1767.text': 'fallback',
  PollEventContent.startType: {
    'kind': kind,
    'max_selections': maxSelections,
    'question': question is String
        ? {'org.matrix.msc1767.text': question}
        : question,
    'answers':
        answers ??
        [
          {'id': 'a', 'org.matrix.msc1767.text': 'Matrix'},
          {'id': 'b', 'org.matrix.msc1767.text': 'XMPP'},
        ],
  },
  'im.fluffychat.poll.quiz': ?quiz,
};

void main() {
  test('a valid disclosed poll', () {
    final content = PollContent.parse(poll())!;
    expect(content.question, 'Which one?');
    expect(content.answers.map((a) => a.id), ['a', 'b']);
    expect(content.maxSelections, 1);
    expect(content.undisclosed, isFalse);
    expect(content.isQuiz, isFalse);
  });

  test('an undisclosed poll', () {
    final content = PollContent.parse(
      poll(kind: 'org.matrix.msc3381.poll.undisclosed'),
    )!;
    expect(content.undisclosed, isTrue);
  });

  test('an unknown kind is disclosed', () {
    expect(PollContent.parse(poll(kind: 'nonsense'))!.undisclosed, isFalse);
    expect(PollContent.parse(poll(kind: 5))!.undisclosed, isFalse);
  });

  test('not a poll', () {
    expect(PollContent.parse(null), isNull);
    expect(PollContent.parse('x'), isNull);
    expect(PollContent.parse({}), isNull);
    expect(PollContent.parse({PollEventContent.startType: 'x'}), isNull);
  });

  test('the question must be a non-empty string', () {
    expect(PollContent.parse(poll(question: 5)), isNull);
    expect(PollContent.parse(poll(question: '   ')), isNull);
    expect(PollContent.parse(poll(question: {'body': 5})), isNull);
    expect(
      PollContent.parse(poll(question: {'body': 'legacy'}))!.question,
      'legacy',
    );
  });

  test('a long question is cut to 255 graphemes', () {
    final content = PollContent.parse(poll(question: 'q' * 5000))!;
    expect(content.question.characters.length, PollLimits.questionMax);
  });

  test('control and bidi characters are dropped from text', () {
    final content = PollContent.parse(
      poll(question: 'a${String.fromCharCode(0x202e)}b\u0000c\nd'),
    )!;
    expect(content.question, 'a b c d');
  });

  test('at most 20 answers survive, out of at most 64 scanned', () {
    final many = [
      for (var i = 0; i < 100; i++)
        {'id': 'id$i', 'org.matrix.msc1767.text': 'answer $i'},
    ];
    final content = PollContent.parse(poll(answers: many))!;
    expect(content.answers, hasLength(PollLimits.answersParseMax));
    expect(content.answers.last.id, 'id19');
    final junkFirst = [
      for (var i = 0; i < 70; i++) 'junk',
      {'id': 'late', 'org.matrix.msc1767.text': 'late'},
      {'id': 'later', 'org.matrix.msc1767.text': 'later'},
    ];
    expect(PollContent.parse(poll(answers: junkFirst)), isNull);
  });

  test('answers without a valid id or text are dropped', () {
    final content = PollContent.parse(
      poll(
        answers: [
          {'org.matrix.msc1767.text': 'no id'},
          {'id': 7, 'org.matrix.msc1767.text': 'int id'},
          {'id': '', 'org.matrix.msc1767.text': 'empty id'},
          {'id': 'a/b', 'org.matrix.msc1767.text': 'slash'},
          {'id': 'x' * 65, 'org.matrix.msc1767.text': 'long id'},
          {'id': 'ok1', 'org.matrix.msc1767.text': 'one'},
          {'id': 'ok2', 'org.matrix.msc1767.text': 5},
          {'id': 'ok3', 'org.matrix.msc1767.text': '   '},
          {'id': 'ok4', 'org.matrix.msc1767.text': 'four'},
        ],
      ),
    )!;
    expect(content.answers.map((a) => a.id), ['ok1', 'ok4']);
  });

  test('a duplicate id drops the later answer', () {
    final content = PollContent.parse(
      poll(
        answers: [
          {'id': 'a', 'org.matrix.msc1767.text': 'first'},
          {'id': 'a', 'org.matrix.msc1767.text': 'second'},
          {'id': 'b', 'org.matrix.msc1767.text': 'third'},
        ],
      ),
    )!;
    expect(content.answers.map((a) => a.text), ['first', 'third']);
  });

  test('fewer than two valid answers is not a poll', () {
    expect(
      PollContent.parse(
        poll(
          answers: [
            {'id': 'a', 'org.matrix.msc1767.text': 'only'},
          ],
        ),
      ),
      isNull,
    );
    expect(PollContent.parse(poll(answers: 'x')), isNull);
  });

  test('answer text is cut to 100 graphemes', () {
    final content = PollContent.parse(
      poll(
        answers: [
          {'id': 'a', 'org.matrix.msc1767.text': 'z' * 500},
          {'id': 'b', 'org.matrix.msc1767.text': 'y'},
        ],
      ),
    )!;
    expect(content.answers.first.text.characters.length, PollLimits.answerMax);
  });

  test('max_selections is clamped into 1..answers', () {
    for (final entry in {
      0: 1,
      -3: 1,
      1: 1,
      2: 2,
      99: 2,
      '2': 1,
      null: 1,
      1.5: 1,
    }.entries) {
      expect(
        PollContent.parse(poll(maxSelections: entry.key))!.maxSelections,
        entry.value,
        reason: '${entry.key}',
      );
    }
  });

  group('quiz', () {
    Map<String, Object?> quizOf(Object? ids) => {'correct_answer_ids': ids};

    test('a valid quiz', () {
      final content = PollContent.parse(poll(quiz: quizOf(['b'])))!;
      expect(content.isQuiz, isTrue);
      expect(content.quizCorrectIds, {'b'});
    });

    test('an id that is not an answer makes it a normal poll', () {
      expect(PollContent.parse(poll(quiz: quizOf(['zzz'])))!.isQuiz, isFalse);
    });

    test('two correct ids make it a normal poll', () {
      expect(
        PollContent.parse(poll(quiz: quizOf(['a', 'b'])))!.isQuiz,
        isFalse,
      );
    });

    test('wrong shapes make it a normal poll', () {
      for (final quiz in <Object?>[
        'x',
        5,
        quizOf('a'),
        quizOf([5]),
        quizOf([]),
        quizOf(null),
        <String, Object?>{},
      ]) {
        expect(
          PollContent.parse(poll(quiz: quiz))!.isQuiz,
          isFalse,
          reason: '$quiz',
        );
      }
    });
  });

  test('random garbage never throws', () {
    final random = Random(7);
    Object? junk(int depth) {
      switch (random.nextInt(depth > 3 ? 4 : 7)) {
        case 0:
          return null;
        case 1:
          return random.nextInt(1000) - 500;
        case 2:
          return 'text ${random.nextInt(99)}';
        case 3:
          return random.nextBool();
        case 4:
          return [for (var i = 0; i < random.nextInt(5); i++) junk(depth + 1)];
        default:
          return {
            for (final key in [
              PollEventContent.startType,
              'question',
              'answers',
              'id',
              'org.matrix.msc1767.text',
              'max_selections',
              'kind',
              pollQuizKey,
              'correct_answer_ids',
              'body',
            ])
              if (random.nextBool()) key: junk(depth + 1),
          };
      }
    }

    for (var i = 0; i < 200; i++) {
      expect(() => PollContent.parse(junk(0)), returnsNormally);
    }
  });
  group('canVote', () {
    PollContent parsed({bool quiz = true}) => PollContent.parse(
      poll(
        quiz: quiz
            ? {
                'correct_answer_ids': ['b'],
              }
            : null,
      ),
    )!;

    test('a quiz is open until the viewer has voted', () {
      expect(parsed().canVote(mine: const {}, ended: false), isTrue);
      expect(parsed().canVote(mine: {'a'}, ended: false), isFalse);
    });

    test('an ordinary poll can be changed, until it ends', () {
      expect(parsed(quiz: false).canVote(mine: {'a'}, ended: false), isTrue);
      expect(parsed(quiz: false).canVote(mine: {'a'}, ended: true), isFalse);
      expect(parsed().canVote(mine: const {}, ended: true), isFalse);
    });
  });

  group('markFor', () {
    PollContent quiz() => PollContent.parse(
      poll(
        quiz: {
          'correct_answer_ids': ['b'],
        },
      ),
    )!;

    test('nothing is shown before the viewer has voted', () {
      for (final id in ['a', 'b']) {
        expect(
          quiz().markFor(id, mine: const {}, ended: false),
          PollQuizMark.none,
        );
      }
    });

    test('a right vote marks the right answer', () {
      expect(
        quiz().markFor('b', mine: {'b'}, ended: false),
        PollQuizMark.correct,
      );
      expect(quiz().markFor('a', mine: {'b'}, ended: false), PollQuizMark.none);
    });

    test('a wrong vote is marked and the right answer is shown', () {
      expect(
        quiz().markFor('a', mine: {'a'}, ended: false),
        PollQuizMark.wrong,
      );
      expect(
        quiz().markFor('b', mine: {'a'}, ended: false),
        PollQuizMark.correct,
      );
    });

    test('an ended poll shows the answer to people who did not vote', () {
      expect(
        quiz().markFor('b', mine: const {}, ended: true),
        PollQuizMark.correct,
      );
      expect(
        quiz().markFor('a', mine: const {}, ended: true),
        PollQuizMark.none,
      );
    });

    test('a normal poll never shows marks', () {
      final normal = PollContent.parse(poll())!;
      expect(normal.markFor('a', mine: {'a'}, ended: true), PollQuizMark.none);
    });
  });
}
