// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/matrix_room_id.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/search_kind.dart';

enum DatePreset { any, today, week, month, custom }

/// A custom date window, whole local days, inclusive.
@immutable
class DateWindow {
  const DateWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is DateWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The facets of the search filter sheet (DESIGN 9.23).
@immutable
class MessageSearchFilter {
  const MessageSearchFilter({
    this.fromIds = const {},
    this.inRoomIds = const {},
    this.date = DatePreset.any,
    this.custom,
    this.types = const {},
    this.mentionsMe = false,
  });

  static const maxFrom = 10;
  static const maxRooms = 20;
  static final _earliest = DateTime(2000);

  static const none = MessageSearchFilter();

  final Set<String> fromIds;
  final Set<String> inRoomIds;
  final DatePreset date;
  final DateWindow? custom;
  final Set<SearchType> types;
  final bool mentionsMe;

  bool get isEmpty =>
      fromIds.isEmpty &&
      inRoomIds.isEmpty &&
      effectiveDate == DatePreset.any &&
      types.isEmpty &&
      !mentionsMe;

  /// One per facet group that restricts the result (the badge of the sheet).
  int get activeCount =>
      (fromIds.isEmpty ? 0 : 1) +
      (inRoomIds.isEmpty ? 0 : 1) +
      (effectiveDate == DatePreset.any ? 0 : 1) +
      (types.isEmpty ? 0 : 1) +
      (mentionsMe ? 1 : 0);

  /// A custom date without a usable window is no date filter at all.
  DatePreset get effectiveDate =>
      date == DatePreset.custom && custom == null ? DatePreset.any : date;

  static bool _isUserId(String id) =>
      id.isValidMatrixIdStrict() && id.startsWith('@');

  MessageSearchFilter copyWith({
    Set<String>? fromIds,
    Set<String>? inRoomIds,
    DatePreset? date,
    DateWindow? custom,
    bool clearCustom = false,
    Set<SearchType>? types,
    bool? mentionsMe,
  }) => MessageSearchFilter(
    fromIds: fromIds == null
        ? this.fromIds
        : Set.unmodifiable(fromIds.where(_isUserId).take(maxFrom).toSet()),
    inRoomIds: inRoomIds == null
        ? this.inRoomIds
        : Set.unmodifiable(
            inRoomIds.where(isMatrixRoomId).take(maxRooms).toSet(),
          ),
    date: date ?? this.date,
    custom: clearCustom ? null : custom ?? this.custom,
    types: types == null ? this.types : Set.unmodifiable(types),
    mentionsMe: mentionsMe ?? this.mentionsMe,
  );

  /// Whole local days from [from] to [to]: both ends are pulled inside
  /// 2000-01-01..tomorrow. Null when the end is before the start.
  static DateWindow? window(DateTime from, DateTime to, {DateTime? now}) {
    final limit = (now ?? DateTime.now()).add(const Duration(days: 1));
    var start = from;
    var end = to;
    if (start.isBefore(_earliest)) start = _earliest;
    if (end.isAfter(limit)) end = limit;
    if (end.isBefore(start)) return null;
    return DateWindow(
      DateTime(start.year, start.month, start.day),
      DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
    );
  }

  bool matches(IndexedMessage message, DateTime now) {
    if (fromIds.isNotEmpty && !fromIds.contains(message.senderId)) {
      return false;
    }
    if (inRoomIds.isNotEmpty && !inRoomIds.contains(message.roomId)) {
      return false;
    }
    if (mentionsMe && !message.mentionsMe) return false;
    if (types.isNotEmpty &&
        !types.any(
          (type) => type.accepts(message.kind, hasLink: message.hasLink),
        )) {
      return false;
    }
    return matchesDate(
      DateTime.fromMillisecondsSinceEpoch(message.timestamp),
      now,
    );
  }

  bool matchesDate(DateTime at, DateTime now) {
    switch (effectiveDate) {
      case DatePreset.any:
        return true;
      case DatePreset.today:
        final local = now.toLocal();
        return !at.isBefore(DateTime(local.year, local.month, local.day));
      case DatePreset.week:
        return !at.isBefore(now.subtract(const Duration(days: 7)));
      case DatePreset.month:
        return !at.isBefore(now.subtract(const Duration(days: 30)));
      case DatePreset.custom:
        final window = custom!;
        return !at.isBefore(window.start) && !at.isAfter(window.end);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MessageSearchFilter &&
      setEquals(other.fromIds, fromIds) &&
      setEquals(other.inRoomIds, inRoomIds) &&
      other.date == date &&
      other.custom == custom &&
      setEquals(other.types, types) &&
      other.mentionsMe == mentionsMe;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(fromIds),
    Object.hashAllUnordered(inRoomIds),
    date,
    custom,
    Object.hashAllUnordered(types),
    mentionsMe,
  );
}
