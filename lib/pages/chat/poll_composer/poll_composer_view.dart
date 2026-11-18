// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/poll_composer/poll_composer.dart';
import 'package:fluffychat/utils/polls/poll_content.dart';
import 'package:material_ui/material_ui.dart';

class PollComposerView extends StatelessWidget {
  const PollComposerView(this.controller, {super.key});

  final PollComposerController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final message = switch (c.error) {
      PollDraftError.duplicateAnswer => l10n.pollDuplicateAnswer,
      PollDraftError.quizNeedsCorrect when c.quiz =>
        l10n.pollNeedsCorrectAnswer,
      _ => null,
    };
    return Material(
      color: tokens.bg,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 14,
            end: 14,
            bottom: 14 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: AppSchedule.sheetHandleWidth,
                  height: AppSchedule.sheetHandleHeight,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _Header(c),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel(l10n.pollQuestionHeader),
                      _Card(
                        child: TextField(
                          key: const ValueKey('poll_question_field'),
                          controller: c.question,
                          onChanged: c.changed,
                          maxLength: PollLimits.questionMax,
                          minLines: 1,
                          maxLines: 4,
                          style: TextStyle(
                            color: tokens.fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.pollQuestion,
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionLabel(
                        c.quiz
                            ? l10n.pollAnswersHeaderQuiz
                            : l10n.pollAnswersHeader,
                      ),
                      _Card(
                        child: Column(
                          children: [
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              onReorderItem: c.reorder,
                              children: [
                                for (var i = 0; i < c.answers.length; i++)
                                  _AnswerRow(
                                    key: c.answers[i].key,
                                    controller: c,
                                    index: i,
                                  ),
                              ],
                            ),
                            if (c.canAddAnswer)
                              _AddRow(
                                label: l10n.addAnswerOption,
                                onTap: c.addAnswer,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Card(
                        child: Column(
                          children: [
                            _ToggleRow(
                              key: const ValueKey('poll_multiple'),
                              icon: Icons.checklist_rounded,
                              title: l10n.pollMultipleAnswers,
                              subtitle: l10n.pollMultipleAnswersSub,
                              value: c.multiple,
                              onChanged: c.toggleMultiple,
                            ),
                            _ToggleRow(
                              key: const ValueKey('poll_hide_results'),
                              icon: Icons.visibility_off_rounded,
                              title: l10n.pollHideResults,
                              subtitle: l10n.pollHideResultsSub,
                              value: c.hideResults,
                              onChanged: c.toggleHideResults,
                            ),
                            _ToggleRow(
                              key: const ValueKey('poll_quiz'),
                              icon: Icons.quiz_rounded,
                              title: l10n.pollQuiz,
                              subtitle: l10n.pollQuizSub,
                              value: c.quiz,
                              onChanged: c.toggleQuiz,
                            ),
                          ],
                        ),
                      ),
                      _Note(text: l10n.pollVotesVisibleNote),
                      if (c.quiz) _Note(text: l10n.pollQuizNote),
                      if (message != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: 10,
                            start: 6,
                          ),
                          child: Text(
                            message,
                            key: const ValueKey('poll_error'),
                            style: TextStyle(color: tokens.red, fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              _CreateButton(
                label: l10n.createPoll,
                enabled: c.canCreate,
                onTap: c.create,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.controller);

  final PollComposerController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('poll_cancel'),
                onPressed: controller.close,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: tokens.acc,
                ),
                child: Text(
                  l10n.cancel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              l10n.newPoll,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.fg,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 76),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 18, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppTokens.of(context).mut,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.48,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.of(context).surf,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 6, end: 6, top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.xs,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppTokens.of(context).mut,
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTokens.of(context).mut,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.controller, required this.index, super.key});

  final PollComposerController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final answer = c.answers[index];
    final number = index + 1;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.line)),
        ),
        child: Row(
          children: [
            Semantics(
              button: c.quiz,
              checked: c.quiz ? answer.correct : null,
              label: c.quiz ? l10n.markAnswerCorrect('$number') : null,
              excludeSemantics: c.quiz,
              onTap: c.quiz ? () => c.markCorrect(answer) : null,
              child: IconButton(
                key: ValueKey('poll_correct_$index'),
                onPressed: c.quiz ? () => c.markCorrect(answer) : null,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  answer.correct
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: answer.correct ? tokens.ok : tokens.mut,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: ValueKey('poll_answer_$index'),
                controller: answer.text,
                onChanged: c.changed,
                maxLength: PollLimits.answerMax,
                style: TextStyle(color: tokens.fg, fontSize: 15.5),
                decoration: InputDecoration(
                  hintText: l10n.answerOption,
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (c.canRemoveAnswer)
              IconButton(
                key: ValueKey('poll_remove_$index'),
                tooltip: l10n.delete,
                onPressed: () => c.removeAnswer(answer),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(Icons.close_rounded, size: 20, color: tokens.mut),
              ),
            Semantics(
              label: l10n.moveAnswer('$number'),
              child: ReorderableDragStartListener(
                index: index,
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: tokens.mut,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return InkWell(
      key: const ValueKey('poll_add_answer'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
          child: Row(
            spacing: AppSpacing.l,
            children: [
              Icon(Icons.add_rounded, size: 22, color: tokens.acc),
              Text(
                label,
                style: TextStyle(
                  color: tokens.acc,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, size: 21, color: tokens.acc),
      title: Text(
        title,
        style: TextStyle(
          color: tokens.fg,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: tokens.mut, fontSize: 12.5),
      ),
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        color: enabled ? tokens.acc : tokens.surf2,
        borderRadius: BorderRadius.circular(AppSchedule.primaryButton / 2),
        child: InkWell(
          key: const ValueKey('poll_create'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSchedule.primaryButton / 2),
          child: SizedBox(
            height: AppSchedule.primaryButton,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? tokens.onacc : tokens.mut,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
