// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/export/export_events.dart';
import 'package:odango/utils/export/export_html.dart';
import 'package:odango/utils/export/export_json.dart';
import 'package:odango/utils/export/export_media.dart';
import 'package:odango/utils/export/export_model.dart';
import 'package:odango/utils/retention/retention_policy.dart';

/// What the runner needs from a timeline; the SDK one is [SdkExportTimeline].
abstract class ExportTimeline {
  List<Event> get events;
  bool get canLoadMore;
  Future<void> loadMore();
  Event display(Event event);

  /// Called when the export is over, however it ended.
  void dispose() {}
}

class SdkExportTimeline implements ExportTimeline {
  SdkExportTimeline(this.timeline);

  final Timeline timeline;

  @override
  List<Event> get events => timeline.events;

  @override
  bool get canLoadMore => timeline.canRequestHistory;

  @override
  Future<void> loadMore() =>
      timeline.requestHistory(historyCount: ExportLimits.pageSize);

  @override
  Event display(Event event) => event.getDisplayEvent(timeline);

  @override
  void dispose() => timeline.cancelSubscriptions();
}

typedef MediaDownloader = Future<Uint8List?> Function(Event event);

class ChatExportTexts {
  const ChatExportTexts({
    required this.undecryptable,
    required this.truncated,
    required this.mediaSkipped,
  });

  final String undecryptable;
  final String truncated;
  final String mediaSkipped;
}

/// Builds an export in memory. It touches no file and no network beyond the
/// timeline and media the app already reads, and it stops at its caps.
class ChatExportRunner {
  ChatExportRunner({
    required this.timeline,
    required this.roomId,
    required this.roomName,
    required this.encrypted,
    required this.texts,
    required this.downloadMedia,
    this.topic,
    this.retention,
    DateTime Function()? now,
    this.maxEvents = ExportLimits.maxEvents,
    this.maxDuration = ExportLimits.maxDuration,
  }) : _now = now ?? DateTime.now;

  final ExportTimeline timeline;
  final String roomId;
  final String roomName;
  final String? topic;
  final bool encrypted;
  final ChatExportTexts texts;
  final MediaDownloader downloadMedia;
  final RetentionPolicy? retention;
  final DateTime Function() _now;
  final int maxEvents;
  final Duration maxDuration;

  static String fileSafe(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final cut = cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
    return cut.isEmpty || cut == '_' ? 'chat' : cut;
  }

  void _check(ExportCancel? cancel) {
    if (cancel?.isCancelled ?? false) throw const ExportCancelled();
  }

  Future<ChatExportResult> run(
    ExportOptions options, {
    void Function(int events)? onProgress,
    ExportCancel? cancel,
  }) async {
    try {
      return await _run(options, onProgress, cancel);
    } finally {
      timeline.dispose();
    }
  }

  Future<ChatExportResult> _run(
    ExportOptions options,
    void Function(int events)? onProgress,
    ExportCancel? cancel,
  ) async {
    final started = _now();
    var truncated = false;
    _check(cancel);
    while (timeline.canLoadMore) {
      if (timeline.events.length >= maxEvents) {
        truncated = true;
        break;
      }
      if (_now().difference(started) > maxDuration) {
        truncated = true;
        break;
      }
      final before = timeline.events.length;
      await timeline.loadMore();
      _check(cancel);
      onProgress?.call(timeline.events.length);
      if (timeline.events.length == before) break;
    }
    if (timeline.events.length > maxEvents) {
      truncated = true;
    }

    final now = _now();
    final sources = timeline.events.take(maxEvents).toList()
      ..sort((a, b) {
        final byTime = a.originServerTs.compareTo(b.originServerTs);
        return byTime != 0 ? byTime : a.eventId.compareTo(b.eventId);
      });
    final events = <ExportEvent>[];
    final originals = <Event>[];
    for (final source in sources) {
      if (!isExportable(source)) continue;
      if (retention?.hides(source, now) ?? false) continue;
      events.add(
        exportEventFrom(
          source,
          timeline.display(source),
          undecryptableText: texts.undecryptable,
        ),
      );
      originals.add(source);
    }

    final meta = ExportMeta(
      roomId: roomId,
      roomName: roomName,
      topic: topic,
      encrypted: encrypted,
      exportedAt: now,
      truncated: truncated,
    );

    final archive = Archive();
    final mediaPaths = <int, String>{};
    var skipped = 0;
    if (options.media.isNotEmpty) {
      final budget = MediaBudget();
      var fileNumber = 0;
      var rejected = 0;
      var stopped = false;
      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        final kind = event.mediaKind;
        if (kind == null || !options.media.contains(kind)) continue;
        fileNumber++;
        _check(cancel);
        stopped =
            stopped ||
            rejected >= ExportLimits.maxRejectedDownloads ||
            _now().difference(started) > maxDuration;
        final claimed = event.mediaSize;
        if (stopped || claimed == null || !budget.couldFit(claimed)) {
          skipped++;
          continue;
        }
        Uint8List? bytes;
        try {
          bytes = await downloadMedia(originals[i]);
        } catch (_) {
          bytes = null;
        }
        _check(cancel);
        if (bytes == null) {
          skipped++;
          continue;
        }
        if (!budget.take(bytes.length)) {
          skipped++;
          rejected++;
          continue;
        }
        final name = safeMediaName(fileNumber, event.mediaName ?? '');
        archive.addFile(ArchiveFile.bytes('media/$name', bytes));
        mediaPaths[i] = 'media/$name';
      }
    }

    final isHtml = options.format == ExportFormat.html;
    final text = isHtml
        ? buildHtml(
            meta,
            events,
            mediaPaths: mediaPaths,
            truncatedNote: texts.truncated,
            mediaSkippedNote: skipped > 0 ? texts.mediaSkipped : '',
          )
        : buildJson(meta, events);
    final textBytes = utf8.encoder.convert(text);
    if (textBytes.length > ExportLimits.maxTextOutputBytes) {
      throw const ExportTooLarge();
    }
    final date = now.toUtc();
    final stamp =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final base = 'export-${fileSafe(roomName)}-$stamp';
    final extension = isHtml ? 'html' : 'json';
    if (archive.isEmpty) {
      return ChatExportResult(
        bytes: textBytes,
        fileName: '$base.$extension',
        mimeType: isHtml ? 'text/html' : 'application/json',
        eventCount: events.length,
        skippedMedia: skipped,
        truncated: truncated,
      );
    }
    archive.addFile(ArchiveFile.bytes('chat.$extension', textBytes));
    return ChatExportResult(
      bytes: ZipEncoder().encodeBytes(archive),
      fileName: '$base.zip',
      mimeType: 'application/zip',
      eventCount: events.length,
      skippedMedia: skipped,
      truncated: truncated,
    );
  }
}
