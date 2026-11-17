// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/rich_text/outgoing_message.dart';
import 'package:fluffychat/utils/rich_text/rich_mentions.dart';
import 'package:matrix/matrix.dart';

/// The event content of a formatted message, shared by the normal send path
/// and the scheduled one so both stay identical.
Map<String, Object?> richMessageContent(
  Room room,
  RichOutgoing outgoing, {
  String? repliedToSender,
}) {
  final mentions = richMentions(
    plainText: outgoing.plainText,
    resolve: room.getMention,
    ownUserId: room.client.userID,
    repliedToSender: repliedToSender,
  );
  return {
    'msgtype': MessageTypes.Text,
    'body': outgoing.message.body,
    'format': 'org.matrix.custom.html',
    'formatted_body': outgoing.message.formattedBody,
    'm.mentions': ?mentions,
  };
}

/// Sends a formatted message. The SDK wraps replies and edits and encrypts the
/// event like any other.
Future<String?> sendRichMessage(
  Room room,
  RichOutgoing outgoing, {
  Event? inReplyTo,
  String? editEventId,
  String? threadRootEventId,
}) => room.sendEvent(
  richMessageContent(room, outgoing, repliedToSender: inReplyTo?.senderId),
  inReplyTo: inReplyTo,
  editEventId: editEventId,
  threadRootEventId: threadRootEventId,
);
