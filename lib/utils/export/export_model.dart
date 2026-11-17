// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

enum ExportFormat { html, json }

enum ExportMediaKind { photosVideos, files, voice }

/// Every cap of the export. A chat is untrusted input and so is the size it
/// claims: all of them are enforced on the bytes actually read.
abstract class ExportLimits {
  static const maxEvents = 50000;
  static const maxDuration = Duration(minutes: 15);
  static const maxTextOutputBytes = 64 * 1024 * 1024;
  static const maxTextPerMessage = 65536;
  static const maxMediaPerFile = 25 * 1024 * 1024;
  static const maxMediaTotal = 200 * 1024 * 1024;
  static const maxRejectedDownloads = 5;
  static const maxJsonDepth = 8;
  static const maxJsonNodes = 5000;
  static const pageSize = 100;
}

class ExportMeta {
  const ExportMeta({
    required this.roomId,
    required this.roomName,
    required this.encrypted,
    required this.exportedAt,
    this.topic,
    this.truncated = false,
  });

  final String roomId;
  final String roomName;
  final bool encrypted;
  final DateTime exportedAt;
  final String? topic;
  final bool truncated;
}

class ExportEvent {
  const ExportEvent({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    required this.time,
    required this.type,
    required this.text,
    required this.content,
    this.mediaKind,
    this.mediaName,
    this.mediaSize,
  });

  final String eventId;
  final String senderId;
  final String senderName;
  final DateTime time;
  final String type;
  final String text;
  final Map<String, Object?> content;
  final ExportMediaKind? mediaKind;
  final String? mediaName;
  final int? mediaSize;
}

class ExportOptions {
  const ExportOptions({required this.format, this.media = const {}});

  final ExportFormat format;
  final Set<ExportMediaKind> media;
}

class ChatExportResult {
  const ChatExportResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.eventCount,
    required this.skippedMedia,
    required this.truncated,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int eventCount;
  final int skippedMedia;
  final bool truncated;
}

class ExportCancelled implements Exception {
  const ExportCancelled();
}

class ExportTooLarge implements Exception {
  const ExportTooLarge();
}

class ExportCancel {
  bool isCancelled = false;
}
