// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SeenByRow extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  const SeenByRow({super.key, required this.event, required this.timeline});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: event.room.client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[event.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.receipt',
            ) ??
            false,
      ),
      builder: (context, asyncSnapshot) {
        final seenByUsers = event.room.getSeenByUsers(
          timeline,
          eventId: event.eventId,
        );
        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth,
            ),
            child: SeenByView(
              users: [
                for (final user in seenByUsers)
                  SeenUser(
                    id: user.id,
                    name: user.calcDisplayname(),
                    avatar: user.avatarUrl,
                  ),
              ],
              alignEnd: event.senderId == Matrix.of(context).client.userID,
              client: event.room.client,
            ),
          ),
        );
      },
    );
  }
}

class SeenUser {
  final String id;
  final String name;
  final Uri? avatar;

  const SeenUser({required this.id, required this.name, this.avatar});
}

/// "Seen by Mara, Jonas +2" with up to three overlapping avatars (DESIGN.md
/// 7.7). Names come from other people: single line, at most two of them.
class SeenByView extends StatelessWidget {
  static const maxNames = 2;
  static const maxAvatars = 3;

  final List<SeenUser> users;
  final bool alignEnd;
  final Client? client;

  const SeenByView({
    required this.users,
    required this.alignEnd,
    this.client,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final names = users
        .take(maxNames)
        .map((user) => safeDisplayText(user.name, maxGraphemes: 32))
        .join(', ');
    final more = users.length - maxNames;
    final label = more > 0 ? l10n.seenByMore(names, more) : l10n.seenBy(names);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        1,
        AppSpacing.s,
        AppSpacing.xxs,
      ),
      child: Align(
        alignment: alignEnd
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.xs,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.55,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.glass,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.fg,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 16,
                width: 16.0 + (users.take(maxAvatars).length - 1) * 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final (i, user) in users.take(maxAvatars).indexed)
                      PositionedDirectional(
                        start: i * 10.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: tokens.surf, width: 1.5),
                          ),
                          child: Avatar(
                            mxContent: user.avatar,
                            name: user.name,
                            colorSeed: user.id,
                            client: client,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
