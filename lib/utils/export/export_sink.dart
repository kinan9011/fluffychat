// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/export/export_model.dart';

typedef ExportSaver =
    Future<String?> Function(BuildContext context, ChatExportResult result);

/// The one place an export leaves the app: the system save dialog, where the
/// user picks the place. Nothing is written before they choose, nothing is
/// written anywhere else, and null means they cancelled.
///
/// On iOS the plugin stages the bytes in the app's temporary directory and
/// never removes them, so that directory is cleared once the dialog is over,
/// whatever the outcome. The other platforms write straight to the chosen
/// place (Android, desktop) or hand the browser a download (web).
Future<String?> saveExport(
  BuildContext context,
  ChatExportResult result,
) async {
  try {
    final saved = await FilePicker.saveFile(
      dialogTitle: L10n.of(context).exportChat,
      fileName: result.fileName,
      mimeType: result.mimeType,
      bytes: result.bytes,
    );
    return saved?.toString();
  } finally {
    await _clearPickerStaging();
  }
}

Future<void> _clearPickerStaging() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await FilePicker.clearTemporaryFiles();
  } catch (e) {
    Logs().w('Could not clear the picker staging files: ${e.runtimeType}');
  }
}
