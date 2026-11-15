// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message_bubble.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;

class PollWidget extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  const PollWidget({required this.event, required this.timeline, super.key});

  void _endPoll(BuildContext context) =>
      showFutureLoadingDialog(context: context, future: event.endPoll);

  void _toggleVote(BuildContext context, String answerId, int maxSelection) {
    final userId = event.room.client.userID!;
    final answerIds = event.getPollResponses(timeline)[userId] ?? {};
    if (!answerIds.remove(answerId)) {
      answerIds.add(answerId);
      if (answerIds.length > maxSelection) {
        answerIds.clear();
        answerIds.add(answerId);
      }
    }

    showFutureLoadingDialog(
      context: context,
      future: () => event.answerPoll(answerIds.toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventContentResult = Result(() => event.parsedPollEventContent);
    final eventContent = eventContentResult.asValue?.value;
    if (eventContent == null) {
      Logs().w('Invalid poll event', eventContentResult.error);
      return const Text('Unable to parse poll event...');
    }
    final responses = event.getPollResponses(timeline);
    final pollHasBeenEnded = event.getPollHasBeenEnded(timeline);
    final canVote =
        event.room.canSendEvent(PollEventContent.responseType) &&
        !pollHasBeenEnded;
    final maxPolls = responses.length;
    final answersVisible =
        eventContent.pollStartContent.kind == PollKind.disclosed ||
        pollHasBeenEnded;

    final userId = event.room.client.userID!;
    return PollView(
      question: eventContent.pollStartContent.question.mText,
      options: [
        for (final answer in eventContent.pollStartContent.answers.take(
          PollView.maxOptions,
        ))
          PollOptionView(
            id: answer.id,
            text: answer.mText,
            selected: responses[userId]?.contains(answer.id) ?? false,
            voters: [
              for (final entry in responses.entries)
                if (entry.value.contains(answer.id))
                  PollVoter(
                    id: entry.key,
                    name:
                        event.room
                            .getState(EventTypes.RoomMember, entry.key)
                            ?.asUser(event.room)
                            .calcDisplayname() ??
                        entry.key.localpart ??
                        entry.key,
                    avatar: event.room
                        .getState(EventTypes.RoomMember, entry.key)
                        ?.asUser(event.room)
                        .avatarUrl,
                  ),
            ],
          ),
      ],
      totalVoters: maxPolls,
      answersVisible: answersVisible,
      canVote: canVote,
      ended: pollHasBeenEnded,
      canEnd: !pollHasBeenEnded && event.senderId == userId,
      outgoing: event.senderId == userId,
      client: event.room.client,
      onVote: (answerId) => _toggleVote(
        context,
        answerId,
        eventContent.pollStartContent.maxSelections,
      ),
      onEnd: () => _endPoll(context),
      onOpenLink: (url) => UrlLauncher(context, url).launchUrl(),
    );
  }
}

class PollVoter {
  final String id;
  final String name;
  final Uri? avatar;

  const PollVoter({required this.id, required this.name, this.avatar});
}

class PollOptionView {
  final String id;
  final String text;
  final bool selected;
  final List<PollVoter> voters;

  const PollOptionView({
    required this.id,
    required this.text,
    required this.selected,
    required this.voters,
  });
}

/// Question, options with percentage bars and the vote count (DESIGN.md
/// 7.10). Question and options are sender controlled: bounded plain text, at
/// most [maxOptions] options.
class PollView extends StatelessWidget {
  static const maxOptions = 20;
  static const maxVoterAvatars = 5;

  final String question;
  final List<PollOptionView> options;
  final int totalVoters;
  final bool answersVisible;
  final bool canVote;
  final bool ended;
  final bool canEnd;
  final bool outgoing;
  final Client? client;
  final void Function(String answerId)? onVote;
  final VoidCallback? onEnd;
  final void Function(String url)? onOpenLink;

  const PollView({
    required this.question,
    required this.options,
    required this.totalVoters,
    required this.answersVisible,
    required this.canVote,
    required this.ended,
    required this.canEnd,
    required this.outgoing,
    this.client,
    this.onVote,
    this.onEnd,
    this.onOpenLink,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = BubbleColors.of(tokens, outgoing: outgoing);
    final l10n = L10n.of(context);
    final shown = options.take(maxOptions).toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 7,
          children: [
            Linkify(
              text: question,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              style: TextStyle(
                color: colors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              options: const LinkifyOptions(humanize: false),
              linkStyle: TextStyle(
                color: colors.link,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: colors.link,
              ),
              onOpen: (url) => onOpenLink?.call(url.url),
            ),
            for (final option in shown)
              _Option(
                option: option,
                totalVoters: totalVoters,
                answersVisible: answersVisible,
                outgoing: outgoing,
                client: client,
                colors: colors,
                onTap: canVote ? () => onVote?.call(option.id) : null,
              ),
            Text(
              [
                if (answersVisible) l10n.countVotes(totalVoters),
                if (!answersVisible) l10n.answersWillBeVisibleWhenPollHasEnded,
                if (ended) l10n.pollHasBeenEnded,
              ].join(' · '),
              style: TextStyle(color: colors.secondary, fontSize: 11.5),
            ),
            if (canEnd)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onEnd,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.link,
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(l10n.endPoll),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final PollOptionView option;
  final int totalVoters;
  final bool answersVisible;
  final bool outgoing;
  final Client? client;
  final BubbleColors colors;
  final VoidCallback? onTap;

  const _Option({
    required this.option,
    required this.totalVoters,
    required this.answersVisible,
    required this.outgoing,
    required this.client,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final ratio = totalVoters == 0 ? 0.0 : option.voters.length / totalVoters;
    return Semantics(
      button: onTap != null,
      checked: option.selected,
      label: option.text,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Row(
                spacing: 4,
                children: [
                  if (option.selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: colors.accent,
                    )
                  else
                    const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      option.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (answersVisible)
                    Text(
                      '${(ratio * 100).round()}%',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              if (answersVisible) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    color: option.selected ? colors.accent : colors.secondary,
                    backgroundColor: outgoing
                        ? colors.secondary.withValues(alpha: 0.3)
                        : tokens.surf2,
                  ),
                ),
                if (option.voters.isNotEmpty)
                  Row(
                    spacing: 2,
                    children: [
                      for (final voter in option.voters.take(
                        PollView.maxVoterAvatars,
                      ))
                        Avatar(
                          mxContent: voter.avatar,
                          name: voter.name,
                          colorSeed: voter.id,
                          client: client,
                          size: 12,
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
