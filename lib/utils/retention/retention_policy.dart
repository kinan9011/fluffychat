// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// What `m.room.retention` says: nothing, a rule this app applies, or content
/// that is there but not applied by this app (set by the server or another
/// app: `max_lifetime` alone, out of range, unknown keys).
enum RetentionState { off, applied, elsewhere }

/// The disappearing-messages timer of a room (`m.room.retention`). It only
/// decides what this app shows: nothing is ever deleted or redacted.
class RetentionPolicy {
  const RetentionPolicy(this.maxLifetime);

  static const eventType = 'm.room.retention';

  /// A hostile or mistaken policy of a few seconds must not blank a chat.
  static const minLifetime = Duration(hours: 1);
  static const maxLifetimeLimit = Duration(days: 365 * 5);
  static const presets = <Duration>[
    Duration(days: 1),
    Duration(days: 7),
    Duration(days: 30),
  ];
  static const _lookAhead = Duration(hours: 24);

  static const _hideableTypes = {
    EventTypes.Message,
    EventTypes.Sticker,
    EventTypes.Encrypted,
    PollEventContent.startType,
  };

  final Duration maxLifetime;

  /// Null when there is nothing to apply: no policy, wrong types, a lifetime
  /// outside [minLifetime]..[maxLifetimeLimit], or `expire_on_clients` not
  /// set (then only the server may remove messages).
  static RetentionPolicy? fromContent(Map<String, Object?>? content) {
    if (content == null) return null;
    final lifetime = content['max_lifetime'];
    if (lifetime is! int) return null;
    if (content['expire_on_clients'] != true) return null;
    final duration = Duration(milliseconds: lifetime);
    if (duration < minLifetime || duration > maxLifetimeLimit) return null;
    return RetentionPolicy(duration);
  }

  static RetentionState stateOf(Map<String, Object?>? content) {
    if (content == null || content.isEmpty) return RetentionState.off;
    if (fromContent(content) != null) return RetentionState.applied;
    return RetentionState.elsewhere;
  }

  /// The state content that sets [lifetime]; null turns the timer off. Keys
  /// of [existing] that this app does not own (`min_lifetime`...) are kept.
  static Map<String, Object?> contentFor(
    Duration? lifetime, {
    Map<String, Object?>? existing,
  }) {
    final content = <String, Object?>{...?existing}
      ..remove('max_lifetime')
      ..remove('expire_on_clients');
    if (lifetime == null) return content;
    return content
      ..['max_lifetime'] = lifetime.inMilliseconds
      ..['expire_on_clients'] = true;
  }

  bool _canHide(Event event) =>
      _hideableTypes.contains(event.type) && event.status.isSynced;

  DateTime _expiry(Event event) => event.originServerTs.add(maxLifetime);

  /// True when [event] is older than the timer. State events, messages that
  /// are still being sent and ones that are not delivered yet stay visible.
  bool hides(Event event, DateTime now) =>
      _canHide(event) && !_expiry(event).isAfter(now);

  /// The next moment a visible message expires, if that is within a day.
  DateTime? nextExpiry(Iterable<Event> events, DateTime now) {
    DateTime? next;
    for (final event in events) {
      if (!_canHide(event)) continue;
      final expiry = _expiry(event);
      if (!expiry.isAfter(now)) continue;
      if (next == null || expiry.isBefore(next)) next = expiry;
    }
    if (next == null || next.difference(now) > _lookAhead) return null;
    return next;
  }
}
