// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Unread and mention state of one topic, worked out on this device from the
/// own threaded receipt and the thread events that are loaded. It is an
/// estimate: events that are not loaded cannot be counted.
abstract class TopicUnread {
  static const maxCount = 99;

  static ({int count, bool mention}) compute({
    required List<Event> threadEvents,
    required DateTime? ownReceiptTimestamp,
    required String? ownUserId,
    required bool Function(Event event) isHighlight,
    required bool roomIsRead,
    DateTime? latestActivity,
    String? latestSenderId,
  }) {
    final receipt = ownReceiptTimestamp;
    if (receipt == null && roomIsRead) return (count: 0, mention: false);
    final unread = threadEvents.where(
      (event) =>
          event.senderId != ownUserId &&
          (receipt == null || event.originServerTs.isAfter(receipt)),
    );
    var count = unread.length;
    final mention = unread.any(
      (event) => isHighlight(event) || _mentionsUser(event, ownUserId),
    );
    final latest = latestActivity;
    if (count == 0 &&
        latest != null &&
        latestSenderId != ownUserId &&
        (receipt == null || latest.isAfter(receipt))) {
      count = 1;
    }
    return (count: count > maxCount ? maxCount : count, mention: mention);
  }

  static bool _mentionsUser(Event event, String? userId) {
    if (userId == null) return false;
    final mentions = event.content['m.mentions'];
    if (mentions is! Map) return false;
    final ids = mentions['user_ids'];
    return ids is List && ids.contains(userId);
  }
}
