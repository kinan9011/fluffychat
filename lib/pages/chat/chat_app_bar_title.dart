// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/themes.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/date_time_extension.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/motion.dart';
import 'package:odango/utils/retention/retention_labels.dart';
import 'package:odango/utils/sync_status_localization.dart';
import 'package:odango/utils/verified_room_extension.dart';
import 'package:odango/widgets/avatar.dart';
import 'package:odango/widgets/presence_builder.dart';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final tokens = AppTokens.of(context);
    final retention = controller.retention;
    return InkWell(
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: controller.room.membership != .join
          ? null
          : () => FluffyThemes.isThreeColumnMode(context)
                ? controller.toggleDisplayChatDetailsColumn()
                : context.go('/rooms/${room.id}/details'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppChat.tapTarget),
        child: Row(
          children: [
            Hero(
              tag: 'content_banner',
              child: Avatar(
                mxContent: room.avatar,
                name: room.getLocalizedDisplayname(
                  MatrixLocals(L10n.of(context)),
                ),
                colorSeed: room.avatarColorSeed,
                size: AppChat.headerAvatar,
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Row(
                    spacing: 4,
                    children: [
                      if (room.allUsersVerified)
                        Semantics(
                          label: L10n.of(context).verified,
                          child: Icon(
                            Icons.verified_user_rounded,
                            color: tokens.ok,
                            size: 15,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          room.getLocalizedDisplayname(
                            MatrixLocals(L10n.of(context)),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: tokens.fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  StreamBuilder(
                    stream: room.client.onSyncStatus.stream,
                    builder: (context, snapshot) {
                      final status =
                          room.client.onSyncStatus.value ??
                          const SyncStatusUpdate(SyncStatus.waitingForResponse);
                      final hide =
                          FluffyThemes.isColumnMode(context) ||
                          (room.client.onSync.value != null &&
                              status.status != SyncStatus.error &&
                              room.client.prevBatch != null);
                      final style = TextStyle(fontSize: 12, color: tokens.fg);
                      return AnimatedSize(
                        duration: motionDuration(
                          context,
                          FluffyThemes.animationDuration,
                        ),
                        child: hide && retention != null
                            ? _DisappearLine(retention.maxLifetime)
                            : hide
                            ? room.isDirectChat
                                  ? PresenceBuilder(
                                      userId: room.directChatMatrixID,
                                      builder: (context, presence) {
                                        final statusMessage = presence
                                            ?.statusMsg
                                            ?.trim();

                                        final lastActiveTimestamp =
                                            presence?.lastActiveTimestamp;

                                        final texts = [
                                          if (presence?.currentlyActive == true)
                                            L10n.of(context).currentlyActive
                                          else if (lastActiveTimestamp != null)
                                            L10n.of(context).lastActiveAgo(
                                              lastActiveTimestamp
                                                  .localizedTimeShort(context),
                                            ),
                                          if (statusMessage != null)
                                            safeDisplayText(
                                              statusMessage,
                                              maxGraphemes: 80,
                                            ),
                                        ];
                                        final text = texts.join(' ◦ ');
                                        if (text.isEmpty) {
                                          return const SizedBox.shrink();
                                        }

                                        return Text(text, style: style);
                                      },
                                    )
                                  : Row(
                                      children: [
                                        if (room.summary.mJoinedMemberCount !=
                                            null)
                                          Text(
                                            L10n.of(context).countParticipants(
                                              (room
                                                          .summary
                                                          .mJoinedMemberCount ??
                                                      1) +
                                                  (room
                                                          .summary
                                                          .mInvitedMemberCount ??
                                                      0),
                                            ),
                                            maxLines: 1,
                                            style: style,
                                          ),
                                        if (room.topic.isNotEmpty) ...[
                                          Text(' ◦ ', style: style),
                                          Expanded(
                                            child: Text(
                                              safeDisplayText(
                                                room.topic,
                                                maxGraphemes: 120,
                                              ),
                                              style: style,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                            : Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 10,
                                    child: CircularProgressIndicator.adaptive(
                                      strokeWidth: 1,
                                      value: status.progress,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      status.calcLocalizedString(context),
                                      style: style,
                                    ),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisappearLine extends StatelessWidget {
  final Duration lifetime;

  const _DisappearLine(this.lifetime);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = L10n.of(
      context,
    ).disappearAfter(formatRetention(L10n.of(context), lifetime));
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        spacing: 3,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: tokens.acc),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tokens.acc,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
