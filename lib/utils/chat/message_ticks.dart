// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

enum Tick { none, sending, sent, seen, error }

/// Delivery state of the own messages. [eventsNewestFirst] is the visible
/// timeline. An own message is seen when it, or any newer event, carries a
/// receipt of somebody else. One pass, keyed by `transactionId ?? eventId`.
Map<String, Tick> ownMessageTicks(
  List<Event> eventsNewestFirst,
  String? ownUserId,
) {
  final ticks = <String, Tick>{};
  var seenFromHere = false;
  for (final event in eventsNewestFirst) {
    final sending = event.status.isSending;
    if (!seenFromHere &&
        !sending &&
        event.receipts.any((receipt) => receipt.user.id != ownUserId)) {
      seenFromHere = true;
    }
    if (event.senderId != ownUserId) continue;
    ticks[event.transactionId ?? event.eventId] = event.status.isError
        ? Tick.error
        : sending
        ? Tick.sending
        : seenFromHere
        ? Tick.seen
        : Tick.sent;
  }
  return ticks;
}
