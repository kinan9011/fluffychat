// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

/// The only place that posts read receipts. [public] defaults to the privacy
/// setting; the private receipt (`m.read.private`) always goes out so the
/// user's own devices keep their unread counts in sync.
Future<void> sendReadMarker(
  Room room,
  String eventId, {
  String? threadId,
  bool? public,
  bool moveFullyRead = true,
}) async {
  final sendPublic = public ?? AppSettings.sendPublicReadReceipts.value;
  if (threadId == null) {
    return room.setReadMarker(
      moveFullyRead ? eventId : null,
      mRead: eventId,
      public: sendPublic,
    );
  }
  await room.client.postReceipt(
    room.id,
    ReceiptType.mReadPrivate,
    eventId,
    threadId: threadId,
  );
  if (!sendPublic) return;
  await room.client.postReceipt(
    room.id,
    ReceiptType.mRead,
    eventId,
    threadId: threadId,
  );
}

/// Sends the threaded receipt of a topic that is being read: the same event
/// is not sent again while a send is running or once the room's own receipt
/// already points at it.
class ThreadReadMarkerSender {
  String? _sending;

  void send(Room room, String threadId, String? eventId) {
    if (eventId == null || !eventId.isValidMatrixIdStrict()) return;
    if (_sending == eventId) return;
    if (room.receiptState.byThread[threadId]?.latestOwnReceipt?.eventId ==
        eventId) {
      return;
    }
    _sending = eventId;
    unawaited(
      sendReadMarker(room, eventId, threadId: threadId)
          .catchError((_) => Logs().w('[Receipt] could not send in a topic'))
          .whenComplete(() {
            if (_sending == eventId) _sending = null;
          }),
    );
  }
}
