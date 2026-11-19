// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/export/export_page_view.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/export/export_model.dart';
import 'package:odango/utils/export/export_runner.dart';
import 'package:odango/utils/export/export_sink.dart';
import 'package:odango/utils/matrix_room_id.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/retention/retention_policy.dart';
import 'package:odango/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:odango/widgets/matrix.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({required this.roomId, super.key});

  final String roomId;

  @override
  ExportController createState() => ExportController();
}

typedef ExportRunnerFactory =
    Future<ChatExportRunner> Function(BuildContext context, Room room);

class ExportController extends State<ExportPage> {
  /// Test seams: how the export is built and where it is saved.
  @visibleForTesting
  static ExportRunnerFactory? runnerOverride;
  @visibleForTesting
  static ExportSaver? saverOverride;

  ExportFormat format = ExportFormat.html;
  final Set<ExportMediaKind> media = {};
  bool running = false;
  int progress = 0;
  ExportCancel? _cancel;
  bool _closing = false;

  Room? get room {
    if (!isMatrixRoomId(widget.roomId)) return null;
    final room = Matrix.of(context).client.getRoomById(widget.roomId);
    return room?.membership == Membership.join ? room : null;
  }

  void closeIfRoomGone() {
    if (_closing || running || room != null) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(Navigator.of(context).maybePop());
    });
  }

  void setFormat(ExportFormat value) => setState(() => format = value);

  void toggleMedia(ExportMediaKind kind, bool on) =>
      setState(() => on ? media.add(kind) : media.remove(kind));

  void cancel() => _cancel?.isCancelled = true;

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  Future<ChatExportRunner> _defaultRunner(
    BuildContext context,
    Room room,
  ) async {
    final l10n = L10n.of(context);
    final timeline = await room.getTimeline();
    return ChatExportRunner(
      timeline: SdkExportTimeline(timeline),
      roomId: room.id,
      roomName: safeDisplayText(
        room.getLocalizedDisplayname(MatrixLocals(l10n)),
        maxGraphemes: 128,
      ),
      topic: room.topic.isEmpty
          ? null
          : safeDisplayText(room.topic, maxGraphemes: 256),
      encrypted: room.encrypted,
      texts: ChatExportTexts(
        undecryptable: l10n.exportUndecryptable,
        truncated: l10n.exportTruncated(ExportLimits.maxEvents),
        mediaSkipped: l10n.exportMediaSkipped,
      ),
      retention: RetentionPolicy.fromContent(
        room.getState(RetentionPolicy.eventType)?.content,
      ),
      downloadMedia: (event) async =>
          (await event.downloadAndDecryptAttachment()).bytes,
    );
  }

  Future<void> start() async {
    if (running) return;
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var target = room;
    if (target == null) return;
    if (target.encrypted) {
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.exportDecryptedTitle,
        message: l10n.exportDecryptedConfirm,
        okLabel: l10n.exportAnyway,
        cancelLabel: l10n.cancel,
      );
      if (consent != OkCancelResult.ok || !mounted) return;
      target = room;
      if (target == null) return;
    }
    final token = _cancel = ExportCancel();
    setState(() {
      running = true;
      progress = 0;
    });
    try {
      final factory = runnerOverride ?? _defaultRunner;
      final runner = await factory(context, target);
      final result = await runner.run(
        ExportOptions(format: format, media: Set.of(media)),
        onProgress: (count) {
          if (!mounted) return;
          if (room == null) token.isCancelled = true;
          setState(() => progress = count);
        },
        cancel: token,
      );
      if (!mounted || token.isCancelled) return;
      final saver = saverOverride ?? saveExport;
      final path = await saver(context, result);
      if (!mounted || path == null) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportSaved)));
    } on ExportCancelled {
      return;
    } catch (e) {
      Logs().w('[Export] failed (${e.runtimeType})');
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
      }
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    closeIfRoomGone();
    return ExportPageView(this);
  }
}
