// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:matrix/matrix.dart';

enum PeekMenuItem { toggleRead, pin, mute, archive, leave, more }

/// The actions toggle, so a menu entry only runs if the room is still in the
/// state its label was written for ([shown]); otherwise "Mark as read" could
/// end up marking the chat unread.
bool peekStillShown(Room room, PeekMenuItem item, bool shown) => switch (item) {
  PeekMenuItem.toggleRead => room.isUnread == shown,
  PeekMenuItem.pin => room.isFavourite == shown,
  PeekMenuItem.mute => (room.pushRuleState != PushRuleState.notify) == shown,
  PeekMenuItem.archive => room.isArchivedChat == shown,
  PeekMenuItem.leave || PeekMenuItem.more => true,
};
