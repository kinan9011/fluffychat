// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/export/export_model.dart';

ExportMediaKind? exportMediaKind(Map<String, Object?> content) {
  final type = content['msgtype'];
  return switch (type) {
    MessageTypes.Image || MessageTypes.Video => ExportMediaKind.photosVideos,
    MessageTypes.File => ExportMediaKind.files,
    MessageTypes.Audio => ExportMediaKind.voice,
    _ => null,
  };
}

int? _claimedSize(Map<String, Object?> content) {
  final info = content['info'];
  if (info is! Map) return null;
  final size = info['size'];
  return size is int ? size : null;
}

/// Whether the export shows this event: messages, stickers and messages that
/// could not be decrypted. Edits are shown merged into the message they edit,
/// redacted events are never shown.
bool isExportable(Event event) {
  if (event.redacted) return false;
  if (event.relationshipType == RelationshipTypes.edit) return false;
  return event.type == EventTypes.Message ||
      event.type == EventTypes.Sticker ||
      event.type == EventTypes.Encrypted;
}

/// The export copy of one event. [display] is the event with its newest
/// edit applied. Only `body` is used as text, never `formatted_body`.
ExportEvent exportEventFrom(
  Event original,
  Event display, {
  required String undecryptableText,
}) {
  final undecryptable = original.type == EventTypes.Encrypted;
  final content = undecryptable
      ? <String, Object?>{}
      : Map<String, Object?>.from(display.content);
  final kind = undecryptable ? null : exportMediaKind(content);
  final rawName = content['filename'] ?? content['body'];
  final text = undecryptable
      ? undecryptableText
      : display.calcUnlocalizedBody(hideReply: true);
  return ExportEvent(
    eventId: original.eventId.length > 256
        ? original.eventId.substring(0, 256)
        : original.eventId,
    senderId: original.senderId,
    senderName: safeDisplayText(
      original.senderFromMemoryOrFallback.calcDisplayname(),
      maxGraphemes: 128,
    ),
    time: original.originServerTs,
    type: undecryptable ? EventTypes.Encrypted : original.type,
    text: text,
    content: content,
    mediaKind: kind,
    mediaName: kind == null
        ? null
        : safeDisplayText(rawName is String ? rawName : '', maxGraphemes: 120),
    mediaSize: kind == null ? null : _claimedSize(content),
  );
}
