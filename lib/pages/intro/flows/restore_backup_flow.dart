// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/utils/backup_dump_validator.dart';
import 'package:odango/utils/file_selector.dart';
import 'package:odango/widgets/future_loading_dialog.dart';
import 'package:odango/widgets/matrix.dart';

Future<void> restoreBackupFlow(BuildContext context) async {
  final matrix = Matrix.of(context);
  final picked = await selectFiles(context);
  final file = picked.firstOrNull;
  if (file == null) return;

  if (!context.mounted) return;
  final result = await showFutureLoadingDialog(
    context: context,
    future: () => importBackupFile(file, (dump) async {
      final client = await matrix.getLoginClient();
      final imported = await client.database.importDump(dump);
      if (!imported) throw const BackupRestoreFailedException();
      await client.init(
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      matrix.initMatrix();
      return client.isLogged();
    }),
  );

  if (result.result == true && context.mounted) {
    context.go('/rooms');
  }
}
