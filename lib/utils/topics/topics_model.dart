// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/topics/topic.dart';
import 'package:fluffychat/utils/topics/topic_loader.dart';
import 'package:fluffychat/utils/topics/topic_unread.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

enum TopicsStatus { loading, ready, failed }

/// The topics of one room for the screens that show them. Memory only.
class TopicsModel {
  TopicsModel(this.room, {TopicLoader? loader})
    : _loader = loader ?? TopicLoader(room);

  final Room room;
  final TopicLoader _loader;
  final topics = ValueNotifier<List<Topic>>(const []);
  final status = ValueNotifier<TopicsStatus>(TopicsStatus.loading);
  var _disposed = false;

  /// [timelineEvents] are the events that are loaded: they add topics that
  /// have no replies yet and give the unread counts.
  Future<void> load(
    Iterable<Event> timelineEvents, {
    bool force = false,
  }) async {
    var listed = const <Topic>[];
    var failed = false;
    try {
      listed = await _loader.load(force: force);
    } on TopicsLoadFailed {
      failed = true;
    }
    if (_disposed) return;
    final next = _annotate(
      TopicLoader.mergeTimelineRoots(listed, timelineEvents),
      timelineEvents,
    );
    if (!listEquals(next, topics.value)) topics.value = next;
    status.value = failed && next.isEmpty
        ? TopicsStatus.failed
        : TopicsStatus.ready;
  }

  List<Topic> _annotate(List<Topic> found, Iterable<Event> events) {
    final own = room.client.userID;
    final byThread = <String, List<Event>>{};
    for (final event in events) {
      if (event.relationshipType != RelationshipTypes.thread) continue;
      final root = event.relationshipEventId;
      if (root != null) (byThread[root] ??= []).add(event);
    }
    final receipts = room.receiptState;
    final global = receipts.global.latestOwnReceipt?.timestamp;
    return [
      for (final topic in found)
        () {
          final receipt =
              receipts
                  .byThread[topic.rootEventId]
                  ?.latestOwnReceipt
                  ?.timestamp ??
              global;
          final unread = TopicUnread.compute(
            threadEvents: byThread[topic.rootEventId] ?? const [],
            ownReceiptTimestamp: receipt,
            ownUserId: own,
            isHighlight: (event) =>
                room.client.pushruleEvaluator.match(event).highlight,
            roomIsRead: !room.isUnread,
            latestActivity: topic.replyCount > 0 ? topic.lastActivity : null,
            latestSenderId: topic.lastSenderId,
          );
          return topic.withUnread(
            unread: unread.count,
            mention: unread.mention,
          );
        }(),
    ];
  }

  void dispose() {
    _disposed = true;
    topics.dispose();
    status.dispose();
  }
}
