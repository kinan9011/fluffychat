// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;
  const UnreadBubble({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = room.isUnreadOrInvited;
    final hasNotifications = room.notificationCount > 0;
    final unreadBubbleSize = unread || room.hasNewMessages
        ? room.notificationCount > 0
              ? 20.0
              : 14.0
        : 0.0;
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      height: unreadBubbleSize,
      width: !hasNotifications && !unread && !room.hasNewMessages
          ? 0
          : (unreadBubbleSize - 9) * room.notificationCount.toString().length +
                9,
      decoration: BoxDecoration(
        color: room.highlightCount > 0
            ? theme.colorScheme.error
            : hasNotifications ||
                  room.markedUnread ||
                  room.membership == .invite
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(unreadBubbleSize),
      ),
      child: hasNotifications || room.markedUnread
          ? Text(
              room.notificationCount.toString(),
              style: TextStyle(
                color: room.highlightCount > 0
                    ? theme.colorScheme.onError
                    : hasNotifications
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: .center,
            )
          : const SizedBox.shrink(),
    );
  }
}

class SpaceUnreadBubble extends StatelessWidget {
  final Room space;
  const SpaceUnreadBubble({required this.space, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final childIds = {for (final child in space.spaceChildren) ?child.roomId};
    final unreadCount = space.client.rooms
        .where((room) => childIds.contains(room.id) && room.isUnreadOrInvited)
        .length;
    if (unreadCount == 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$unreadCount',
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
