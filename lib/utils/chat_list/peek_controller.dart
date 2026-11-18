// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Reads the newest events of a room from the local database. Peeking must
/// leave no trace for other users, so this class never sends receipts,
/// read markers, typing or key requests and never requests history.
class PeekController {
  PeekController(this.room, {this.limit = 20});

  final Room room;
  final int limit;
  final ValueNotifier<List<Event>> events = ValueNotifier(const []);
  Timeline? _timeline;
  bool _closed = false;

  Future<void> open() async {
    final timeline = await room.getTimeline(limit: limit, onUpdate: _update);
    if (_closed) {
      timeline.cancelSubscriptions();
      return;
    }
    _timeline = timeline;
    _update();
  }

  void _update() {
    final timeline = _timeline;
    if (timeline == null || _closed) return;
    events.value = timeline.events
        .filterByVisibleInGui(retention: RetentionPolicy.forRoom(room))
        .take(limit)
        .toList(growable: false);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timeline?.cancelSubscriptions();
    _timeline = null;
    events.dispose();
  }
}
