// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';

import 'message_bubble.dart';

class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final bool ownMessage;
  final Timeline? timeline;

  const ReplyContent(
    this.replyEvent, {
    this.ownMessage = false,
    super.key,
    this.timeline,
  });

  @override
  Widget build(BuildContext context) {
    final timeline = this.timeline;
    final displayEvent = timeline != null
        ? replyEvent.getDisplayEvent(timeline)
        : replyEvent;
    return FutureBuilder<User?>(
      initialData: displayEvent.senderFromMemoryOrFallback,
      future: displayEvent.fetchSenderUser(),
      builder: (context, snapshot) => ReplyQuoteView(
        name:
            snapshot.data?.calcDisplayname() ??
            displayEvent.senderFromMemoryOrFallback.calcDisplayname(),
        text: displayEvent
            .calcLocalizedBodyFallback(
              MatrixLocals(L10n.of(context)),
              withSenderNamePrefix: false,
              hideReply: true,
              plaintextBody: true,
            )
            .trim()
            .replaceAll('\n', ' '),
        outgoing: ownMessage,
      ),
    );
  }
}

/// Quote block inside a bubble (DESIGN.md 7.5): tinted with a 3 px accent
/// border on incoming bubbles, translucent white on outgoing ones. Name and
/// text come from other people, so both are one plain line.
class ReplyQuoteView extends StatelessWidget {
  final String name;
  final String text;
  final bool outgoing;

  const ReplyQuoteView({
    required this.name,
    required this.text,
    required this.outgoing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = BubbleColors.of(tokens, outgoing: outgoing);
    return ClipRRect(
      borderRadius: BorderRadius.circular(outgoing ? 12 : 10),
      child: ColoredBox(
        color: outgoing
            ? tokens.outFg.withValues(alpha: 0.16)
            : tokens.acc.withValues(alpha: 0.14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              if (!outgoing)
                ColoredBox(color: tokens.acc, child: const SizedBox(width: 3)),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: outgoing ? tokens.outFg : tokens.acc,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.secondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
