// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// What the community view needs to know about one child of a space: its
/// power levels (only known for rooms this account is in) and whether this
/// account joined it.
@immutable
class ChildPowerLevels {
  const ChildPowerLevels({
    required this.roomId,
    required this.joined,
    required this.isSpace,
    required this.powerLevels,
    this.encrypted = false,
  });

  final String roomId;
  final bool joined;
  final bool isSpace;
  final Map<String, Object?>? powerLevels;

  /// In an encrypted room, posts are `m.room.encrypted` events.
  final bool encrypted;
}

@immutable
class AnnouncementsRoom {
  const AnnouncementsRoom({
    required this.roomId,
    required this.postingLevel,
    required this.userCanPost,
  });

  final String roomId;
  final int postingLevel;
  final bool userCanPost;
}

/// A community is a space with an announcements room: a group where the
/// power level needed to post is at least moderator. Matrix has no channels;
/// this is only a reading of the power levels of rooms this account is in.
abstract final class CommunityModel {
  static const moderatorLevel = 50;
  static const adminLevel = 100;

  static int _level(Object? value) => value is int ? value : 0;

  /// The level that is needed to send a message: the override for
  /// `m.room.message` (`m.room.encrypted` in an encrypted room) when there is
  /// one, else `events_default`.
  static int postingLevel(
    Map<String, Object?>? powerLevels, {
    bool encrypted = false,
  }) {
    if (powerLevels == null) return 0;
    final events = powerLevels['events'];
    final override = events is Map
        ? events[encrypted ? 'm.room.encrypted' : 'm.room.message']
        : null;
    return override is int ? override : _level(powerLevels['events_default']);
  }

  /// The level of [userId]: its entry in `users`, else `users_default`.
  static int userLevel(Map<String, Object?>? powerLevels, String userId) {
    if (powerLevels == null) return 0;
    final users = powerLevels['users'];
    final own = users is Map ? users[userId] : null;
    return own is int ? own : _level(powerLevels['users_default']);
  }

  /// The first joined child that is a room (not a space) where posting needs
  /// moderator rights or more and ordinary members cannot post. [children]
  /// are in the order of the hierarchy.
  static AnnouncementsRoom? find(
    Iterable<ChildPowerLevels> children, {
    required String ownUserId,
  }) {
    for (final child in children) {
      if (!child.joined || child.isSpace) continue;
      final levels = child.powerLevels;
      if (levels == null) continue;
      final posting = postingLevel(levels, encrypted: child.encrypted);
      if (posting < moderatorLevel) continue;
      if (_level(levels['users_default']) >= posting) continue;
      return AnnouncementsRoom(
        roomId: child.roomId,
        postingLevel: posting,
        userCanPost: userLevel(levels, ownUserId) >= posting,
      );
    }
    return null;
  }
}
