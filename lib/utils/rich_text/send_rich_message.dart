// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/rich_text/outgoing_message.dart';
import 'package:fluffychat/utils/rich_text/rich_mentions.dart';
import 'package:matrix/matrix.dart';

/// Sends a formatted message. The SDK wraps replies and edits and encrypts the
/// event like any other.
Future<String?> sendRichMessage(
  Room room,
  RichOutgoing outgoing, {
  Event? inReplyTo,
  String? editEventId,
  String? threadRootEventId,
}) {
  final mentions = richMentions(
    plainText: outgoing.plainText,
    resolve: room.getMention,
    ownUserId: room.client.userID,
    repliedToSender: inReplyTo?.senderId,
  );
  return room.sendEvent(
    {
      'msgtype': MessageTypes.Text,
      'body': outgoing.message.body,
      'format': 'org.matrix.custom.html',
      'formatted_body': outgoing.message.formattedBody,
      'm.mentions': ?mentions,
    },
    inReplyTo: inReplyTo,
    editEventId: editEventId,
    threadRootEventId: threadRootEventId,
  );
}
