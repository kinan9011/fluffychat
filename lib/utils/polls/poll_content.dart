// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

abstract class PollLimits {
  static const questionMax = 255;
  static const answerMax = 100;
  static const answersMin = 2;
  static const answersSendMax = 10;
  static const answersParseMax = 20;
  static const rawAnswersScanned = 64;
  static const idMax = 64;
  static const bodyMax = 4096;
}

/// Matrix content key of the quiz extension (a client extension, other apps
/// show a normal poll). The correct answer is stored in clear in the event.
const pollQuizKey = 'im.fluffychat.poll.quiz';

final _controlChars = RegExp(r'[\u0000-\u001F\u007F]');

String _clean(String input) =>
    input.replaceAll(_controlChars, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

enum PollDraftError {
  emptyQuestion,
  questionTooLong,
  tooFewAnswers,
  tooManyAnswers,
  emptyAnswer,
  answerTooLong,
  duplicateAnswer,
  quizNeedsCorrect,
  quizWithMultiple,
}

/// A poll the user is about to send.
@immutable
class PollDraft {
  PollDraft({
    required String question,
    required List<String> answers,
    this.multiple = false,
    this.hideResults = false,
    this.quiz = false,
    this.correct = const {},
  }) : question = _clean(question),
       answers = List.unmodifiable(answers.map(_clean));

  final String question;
  final List<String> answers;
  final bool multiple;
  final bool hideResults;
  final bool quiz;

  /// Indexes into [answers].
  final Set<int> correct;

  PollDraftError? validate() {
    if (question.isEmpty) return PollDraftError.emptyQuestion;
    if (question.characters.length > PollLimits.questionMax) {
      return PollDraftError.questionTooLong;
    }
    if (answers.length < PollLimits.answersMin) {
      return PollDraftError.tooFewAnswers;
    }
    if (answers.length > PollLimits.answersSendMax) {
      return PollDraftError.tooManyAnswers;
    }
    final seen = <String>{};
    for (final answer in answers) {
      if (answer.isEmpty) return PollDraftError.emptyAnswer;
      if (answer.characters.length > PollLimits.answerMax) {
        return PollDraftError.answerTooLong;
      }
      if (!seen.add(answer.toLowerCase())) {
        return PollDraftError.duplicateAnswer;
      }
    }
    if (quiz && multiple) return PollDraftError.quizWithMultiple;
    if (quiz && !(correct.length == 1 && correct.single < answers.length)) {
      return PollDraftError.quizNeedsCorrect;
    }
    return null;
  }

  /// The longest prefix of whole grapheme clusters that fits [maxUnits]
  /// UTF-16 units: a cut inside an emoji would leave a lone surrogate, which
  /// canonical-JSON servers refuse.
  static String _fit(String text, int maxUnits) {
    final out = StringBuffer();
    var units = 0;
    for (final cluster in text.characters) {
      if (units + cluster.length > maxUnits) break;
      out.write(cluster);
      units += cluster.length;
    }
    return out.toString();
  }

  /// The content of the `org.matrix.msc3381.poll.start` event. Answer ids are
  /// "1".."n".
  Map<String, Object?> toStartContent() {
    var body = question;
    for (var i = 0; i < answers.length; i++) {
      body = '$body\n${i + 1}. ${answers[i]}';
    }
    if (body.length > PollLimits.bodyMax) body = _fit(body, PollLimits.bodyMax);
    final content = PollEventContent(
      mText: body,
      pollStartContent: PollStartContent(
        kind: hideResults ? PollKind.undisclosed : PollKind.disclosed,
        maxSelections: multiple ? answers.length : 1,
        question: PollQuestion(mText: question),
        answers: [
          for (var i = 0; i < answers.length; i++)
            PollAnswer(id: '${i + 1}', mText: answers[i]),
        ],
      ),
    ).toJson();
    return {
      ...content,
      if (quiz)
        pollQuizKey: {
          'correct_answer_ids': ['${correct.single + 1}'],
        },
    };
  }
}

/// Shown only in a quiz, once the viewer has voted or the poll has ended.
enum PollQuizMark { none, correct, wrong }

@immutable
class PollAnswerView {
  const PollAnswerView({required this.id, required this.text});

  final String id;
  final String text;
}

/// A received poll, bounded: nothing in here is larger than the limits, and
/// it is built from untrusted content without ever throwing.
@immutable
class PollContent {
  const PollContent({
    required this.question,
    required this.answers,
    required this.maxSelections,
    required this.undisclosed,
    required this.quizCorrectIds,
  });

  final String question;
  final List<PollAnswerView> answers;
  final int maxSelections;
  final bool undisclosed;

  /// Empty unless the poll is a valid quiz.
  final Set<String> quizCorrectIds;

  bool get isQuiz => quizCorrectIds.isNotEmpty;

  /// What an option shows in a quiz. Nothing is revealed before the viewer
  /// has voted or the poll has ended.
  PollQuizMark markFor(
    String answerId, {
    required Set<String> mine,
    required bool ended,
  }) {
    if (!isQuiz || (mine.isEmpty && !ended)) return PollQuizMark.none;
    if (quizCorrectIds.contains(answerId)) return PollQuizMark.correct;
    return mine.contains(answerId) ? PollQuizMark.wrong : PollQuizMark.none;
  }

  /// A quiz vote is final: changing it after the answer was shown defeats
  /// the quiz.
  bool canVote({required Set<String> mine, required bool ended}) =>
      !ended && !(isQuiz && mine.isNotEmpty);

  static final _idPattern = RegExp(r'^[A-Za-z0-9_.:\-]+$');

  static PollContent? parse(Object? content) {
    try {
      return _parse(content);
    } catch (_) {
      return null;
    }
  }

  static PollContent? _parse(Object? content) {
    if (content is! Map) return null;
    final start = content[PollEventContent.startType];
    if (start is! Map) return null;
    final question = _text(start['question']);
    if (question == null) return null;
    final rawAnswers = start['answers'];
    if (rawAnswers is! List) return null;
    final answers = <PollAnswerView>[];
    final ids = <String>{};
    for (final raw in rawAnswers.take(PollLimits.rawAnswersScanned)) {
      if (answers.length >= PollLimits.answersParseMax) break;
      if (raw is! Map) continue;
      final id = raw['id'];
      final text = raw[PollEventContent.mTextJsonKey];
      if (id is! String || text is! String) continue;
      if (id.isEmpty || id.length > PollLimits.idMax) continue;
      if (!_idPattern.hasMatch(id)) continue;
      final shown = safeDisplayText(text, maxGraphemes: PollLimits.answerMax);
      if (shown.isEmpty || !ids.add(id)) continue;
      answers.add(PollAnswerView(id: id, text: shown));
    }
    if (answers.length < PollLimits.answersMin) return null;
    final max = start['max_selections'];
    final maxSelections = max is int ? max.clamp(1, answers.length) : 1;
    final quiz = content[pollQuizKey];
    final correct = quiz is Map ? quiz['correct_answer_ids'] : null;
    final quizIds =
        correct is List && correct.length == 1 && correct.single is String
        ? {correct.single as String}
        : <String>{};
    return PollContent(
      question: question,
      answers: answers,
      maxSelections: maxSelections,
      undisclosed: start['kind'] == PollKind.undisclosed.name,
      quizCorrectIds: quizIds.every(ids.contains) ? quizIds : const {},
    );
  }

  static String? _text(Object? question) {
    if (question is! Map) return null;
    final raw = question[PollEventContent.mTextJsonKey] ?? question['body'];
    if (raw is! String) return null;
    final shown = safeDisplayText(raw, maxGraphemes: PollLimits.questionMax);
    return shown.isEmpty ? null : shown;
  }
}
