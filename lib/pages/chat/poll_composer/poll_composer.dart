// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/pages/chat/poll_composer/poll_composer_view.dart';
import 'package:odango/pages/chat/trust_user_key_dialog.dart';
import 'package:odango/utils/adaptive_bottom_sheet.dart';
import 'package:odango/utils/localized_exception_extension.dart';
import 'package:odango/utils/polls/poll_content.dart';

Future<void> showPollComposer(BuildContext context, Room room) =>
    showAdaptiveBottomSheet<void>(
      context: context,
      maxHeight: AppSchedule.sheetMaxHeight,
      builder: (context) => PollComposer(room: room),
    );

/// One answer row. The key keeps the row (and its "correct" mark) together
/// while the list is reordered.
class PollAnswerField {
  PollAnswerField();

  final key = UniqueKey();
  final text = TextEditingController();
  var correct = false;
}

class PollComposer extends StatefulWidget {
  const PollComposer({required this.room, super.key});

  final Room room;

  @override
  State<PollComposer> createState() => PollComposerController();
}

class PollComposerController extends State<PollComposer> {
  final question = TextEditingController();
  final answers = [PollAnswerField(), PollAnswerField()];
  var multiple = false;
  var hideResults = false;
  var quiz = false;
  var sending = false;
  String? _txid;
  String? _txidContent;

  PollDraft get draft => PollDraft(
    question: question.text,
    answers: [for (final answer in answers) answer.text.text],
    multiple: multiple,
    hideResults: hideResults,
    quiz: quiz,
    correct: {
      for (var i = 0; i < answers.length; i++)
        if (answers[i].correct) i,
    },
  );

  PollDraftError? get error => draft.validate();

  bool get canCreate => !sending && error == null;

  bool get canAddAnswer => answers.length < PollLimits.answersSendMax;

  bool get canRemoveAnswer => answers.length > PollLimits.answersMin;

  bool get reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    question.dispose();
    for (final answer in answers) {
      answer.text.dispose();
    }
    super.dispose();
  }

  void changed([_]) => setState(() {});

  void close() => Navigator.of(context).pop();

  void addAnswer() {
    if (!canAddAnswer) return;
    setState(() => answers.add(PollAnswerField()));
  }

  void removeAnswer(PollAnswerField answer) {
    if (!canRemoveAnswer) return;
    setState(() {
      answers.remove(answer);
      answer.text.dispose();
    });
  }

  void reorder(int from, int to) => setState(() {
    final moved = answers.removeAt(from);
    answers.insert(to, moved);
  });

  void toggleMultiple(bool value) => setState(() {
    multiple = value;
    if (value) _setQuiz(false);
  });

  void toggleQuiz(bool value) => setState(() {
    if (value) multiple = false;
    _setQuiz(value);
  });

  void toggleHideResults(bool value) => setState(() => hideResults = value);

  void _setQuiz(bool value) {
    quiz = value;
    if (value) return;
    for (final answer in answers) {
      answer.correct = false;
    }
  }

  void markCorrect(PollAnswerField answer) {
    if (!quiz) return;
    setState(() {
      for (final other in answers) {
        other.correct = other == answer && !other.correct;
      }
    });
  }

  Future<void> create() async {
    if (!canCreate) return;
    final content = draft.toStartContent();
    setState(() => sending = true);
    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!mounted) return;
    if (!proceed) return setState(() => sending = false);
    try {
      final fingerprint = jsonEncode(content);
      if (_txidContent != fingerprint) {
        _txidContent = fingerprint;
        _txid = widget.room.client.generateUniqueTransactionId();
      }
      await widget.room.sendEvent(
        content,
        type: PollEventContent.startType,
        txid: _txid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, s) {
      Logs().w('Unable to create poll', e, s);
      if (!mounted) return;
      setState(() => sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  @override
  Widget build(BuildContext context) => PollComposerView(this);
}
