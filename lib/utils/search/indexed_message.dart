// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/search/search_kind.dart';

/// One searchable message of an encrypted room. Holds plaintext: it only ever
/// lives in memory or inside the encrypted database.
class IndexedMessage {
  const IndexedMessage({
    required this.roomId,
    required this.eventId,
    required this.senderId,
    required this.timestamp,
    required this.kind,
    required this.text,
    this.mentionsMe = false,
    this.hasLink = false,
  });

  final String roomId;
  final String eventId;
  final String senderId;

  /// Milliseconds since the epoch (origin server timestamp).
  final int timestamp;
  final SearchKind kind;
  final String text;
  final bool mentionsMe;
  final bool hasLink;

  String get key => '$roomId\n$eventId';

  IndexedMessage withText(String text, {required bool hasLink}) =>
      IndexedMessage(
        roomId: roomId,
        eventId: eventId,
        senderId: senderId,
        timestamp: timestamp,
        kind: kind,
        text: text,
        mentionsMe: mentionsMe,
        hasLink: hasLink,
      );
}
