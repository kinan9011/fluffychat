// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/matrix_sdk_extensions/chat_list_room_extension.dart';

/// Takes archived chats out of the archive when someone mentions the user
/// again, but only if the user asked for it and only for a mention that is
/// new: the counts are tracked whatever the setting says, and the first time
/// a room is seen only records its count, so switching the setting on or
/// adding an account never acts on old mentions.
class UnarchiveOnMention {
  UnarchiveOnMention(this.client)
    : _seen = {for (final room in client.rooms) room.id: room.highlightCount};

  final Client client;
  final Map<String, int> _seen;

  List<String> roomsToUnarchive(SyncUpdate sync) {
    final result = <String>[];
    final joined = sync.rooms?.join ?? const <String, JoinedRoomUpdate>{};
    for (final entry in joined.entries) {
      final count = entry.value.unreadNotifications?.highlightCount;
      if (count == null) continue;
      final previous = _seen[entry.key];
      _seen[entry.key] = count;
      if (previous == null ||
          !AppSettings.unarchiveOnMention.value ||
          count <= previous) {
        continue;
      }
      if (client.getRoomById(entry.key)?.isArchivedChat ?? false) {
        result.add(entry.key);
      }
    }
    return result;
  }

  Future<void> handle(SyncUpdate sync) async {
    for (final id in roomsToUnarchive(sync)) {
      try {
        await client.getRoomById(id)?.setArchivedChat(false);
      } catch (_) {
        Logs().w('[Unarchive] failed');
      }
    }
  }
}
