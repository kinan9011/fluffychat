// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/pages/chat/events/reaction_pills.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/chat/reaction_summary.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactions(this.event, this.timeline, {super.key});

  @override
  Widget build(BuildContext context) {
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final client = Matrix.of(context).client;
    final summary = summarizeReactions(allReactionEvents, client.userID);
    return ReactionPills(
      summary: summary,
      alignEnd: event.senderId == client.userID,
      client: event.room.client,
      onTap: (entry) {
        if (!entry.own) {
          event.room.sendReaction(event.eventId, entry.key);
          return;
        }
        final own = allReactionEvents.firstWhereOrNull(
          (e) =>
              e.senderId == client.userID &&
              e.content
                      .tryGetMap<String, Object?>('m.relates_to')
                      ?.tryGet<String>('key') ==
                  entry.key,
        );
        if (own == null) return;
        showFutureLoadingDialog(
          context: context,
          future: own.status.isSent ? own.redactEvent : own.cancelSend,
        );
      },
      onLongPress: (entry) => showDialog<void>(
        context: context,
        builder: (context) => _ReactorsDialog(client: client, entry: entry),
      ),
    );
  }
}

class _ReactorsDialog extends StatelessWidget {
  final Client client;
  final ReactionEntry entry;

  const _ReactorsDialog({required this.client, required this.entry});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Center(
      child: Text(entry.key, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
    content: SingleChildScrollView(
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final reactor in entry.reactors)
            Chip(
              avatar: Avatar(
                mxContent: reactor.avatarUrl,
                name: reactor.calcDisplayname(),
                client: client,
                presenceUserId: reactor.stateKey,
              ),
              label: Text(
                safeDisplayText(reactor.calcDisplayname(), maxGraphemes: 40),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ),
  );
}
