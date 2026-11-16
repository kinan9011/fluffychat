// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The `m.mentions` of a formatted message: the algorithm of
/// `Room.sendTextEvent`, applied to the text without format markers.
Map<String, Object?>? richMentions({
  required String plainText,
  required String? Function(String mention) resolve,
  required String? ownUserId,
  String? repliedToSender,
}) {
  var mentions =
      plainText
          .split('@')
          .map(
            (text) => text.startsWith('[')
                ? '@${text.split(']').first}]'
                : '@${text.split(RegExp(r'\s+')).first}',
          )
          .toList()
        ..removeAt(0);
  final room = mentions.remove('@room');
  mentions =
      mentions
          .map(
            (mention) => mention.isValidMatrixIdStrict(strictDomainCheck: true)
                ? mention
                : resolve(mention),
          )
          .nonNulls
          .toSet()
          .toList()
        ..remove(ownUserId);
  if (repliedToSender != null) mentions.add(repliedToSender);
  if (!room && mentions.isEmpty) return null;
  return {
    if (room) 'room': true,
    if (mentions.isNotEmpty) 'user_ids': mentions,
  };
}
