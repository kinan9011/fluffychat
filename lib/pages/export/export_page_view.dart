// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/export/export_page.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/export/export_model.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:fluffychat/widgets/settings/settings_segmented.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:material_ui/material_ui.dart';

class ExportPageView extends StatelessWidget {
  const ExportPageView(this.controller, {super.key});

  final ExportController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final room = controller.room;
    final name = room == null
        ? null
        : safeDisplayText(
            room.getLocalizedDisplayname(MatrixLocals(l10n)),
            maxGraphemes: 60,
          );
    final running = controller.running;
    return SettingsScaffold(
      title: l10n.exportChat,
      subtitle: name,
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSettingsLayout.sideMargin,
          AppSpacing.s,
          AppSettingsLayout.sideMargin,
          AppSpacing.xxl,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const ValueKey('export_button'),
            onPressed: running || room == null ? null : controller.start,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.acc,
              foregroundColor: tokens.onacc,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: Text(l10n.exportAction),
          ),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 18,
            end: 18,
            bottom: 6,
          ),
          child: Text(
            l10n.exportFormat.toUpperCase(),
            style: TextStyle(
              color: tokens.mut,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.48,
            ),
          ),
        ),
        SettingsSegmented<ExportFormat>(
          items: [
            (ExportFormat.html, l10n.exportFormatHtml),
            (ExportFormat.json, l10n.exportFormatJson),
          ],
          value: controller.format,
          onChanged: running ? (_) {} : controller.setFormat,
        ),
        SettingsGroup(
          header: l10n.exportInclude,
          footer: l10n.exportMediaLimit,
          rows: [
            for (final (kind, icon, title) in [
              (
                ExportMediaKind.photosVideos,
                Icons.photo_library_rounded,
                l10n.exportPhotosVideos,
              ),
              (
                ExportMediaKind.files,
                Icons.description_rounded,
                l10n.exportFiles,
              ),
              (ExportMediaKind.voice, Icons.mic_rounded, l10n.exportVoice),
            ])
              SettingsToggleRow(
                key: ValueKey('export_media_${kind.name}'),
                icon: icon,
                title: title,
                value: controller.media.contains(kind),
                onChanged: running
                    ? null
                    : (on) => controller.toggleMedia(kind, on),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 16,
            end: 16,
            bottom: 14,
          ),
          child: Row(
            key: const ValueKey('export_warning'),
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: tokens.warn),
              Expanded(
                child: Text(
                  l10n.exportDecryptedWarning,
                  style: TextStyle(
                    color: tokens.mut,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (running)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 4,
              top: 4,
              end: 4,
              bottom: 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                const LinearProgressIndicator(),
                Text(
                  l10n.exportRunning(controller.progress),
                  style: TextStyle(color: tokens.mut, fontSize: 13),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('export_cancel'),
                    onPressed: controller.cancel,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      foregroundColor: tokens.acc,
                    ),
                    child: Text(l10n.cancel),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
