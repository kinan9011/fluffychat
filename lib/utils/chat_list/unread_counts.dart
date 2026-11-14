// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:matrix/matrix.dart';

int unreadChatCount(Iterable<Room> rooms) =>
    rooms.where((room) => !room.isJoinedSpace && room.isUnreadOrInvited).length;
