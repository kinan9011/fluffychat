// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/rich_text/editor_text.dart';
import 'package:fluffychat/utils/rich_text/format_state.dart';
import 'package:fluffychat/utils/rich_text/html_serializer.dart';

sealed class OutgoingText {
  const OutgoingText();
}

/// Goes through `Room.sendTextEvent` exactly as before (SDK markdown, commands,
/// mentions).
final class PlainOutgoing extends OutgoingText {
  const PlainOutgoing(this.text);

  final String text;
}

/// Goes through [RichHtmlSerializer]; [plainText] has no markers and is what
/// mentions are read from.
final class RichOutgoing extends OutgoingText {
  const RichOutgoing(this.message, this.plainText);

  final RichMessage message;
  final String plainText;
}

final _command = RegExp(r'^/\w+');

/// Decides how the composer text is sent. Throws [RichTextTooLong] when a
/// formatted message exceeds the caps.
OutgoingText planOutgoing(
  String text,
  FormatState format, {
  bool edit = false,
  bool encrypted = false,
}) {
  if (_command.hasMatch(text) || format.isEmpty) return PlainOutgoing(text);
  final document = RichEditorText.build(text, format.ranges);
  if (document.isPlain) return PlainOutgoing(text);
  final message = RichHtmlSerializer.serialize(document);
  if (message.eventBytes(edit: edit, encrypted: encrypted) >
      RichLimits.maxEventBytes) {
    throw const RichTextTooLong('event');
  }
  return RichOutgoing(message, document.plainText);
}
