// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:matrix/matrix.dart';

enum SwipeAction { toggleRead, mute, pin, archive }

Future<void> runSwipeAction(
  Client client,
  String roomId,
  SwipeAction action, {
  required bool publicReceipts,
}) async {
  final room = client.getRoomById(roomId);
  if (room == null || room.membership != Membership.join) return;
  switch (action) {
    case SwipeAction.mute:
      return room.setPushRuleState(
        room.pushRuleState == PushRuleState.notify
            ? PushRuleState.mentionsOnly
            : PushRuleState.notify,
      );
    case SwipeAction.pin:
      if (room.isFavourite) return room.removeTag(TagType.favourite);
      return room.addTag(
        TagType.favourite,
        order: pinOrderForNew(
          client.rooms.where((r) => r.isFavourite).map((r) => r.pinOrder),
        ),
      );
    case SwipeAction.archive:
      return room.setArchivedChat(!room.isArchivedChat);
    case SwipeAction.toggleRead:
      if (!room.isUnread) return room.markUnread(true);
      if (room.markedUnread) await room.markUnread(false);
      final last = room.lastEvent;
      if (last == null ||
          !last.status.isSynced ||
          !(room.notificationCount > 0 || room.hasNewMessages)) {
        return;
      }
      return room.setReadMarker(
        last.eventId,
        mRead: last.eventId,
        public: publicReceipts,
      );
  }
}
