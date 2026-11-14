// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_quarantine_notice.dart';
import 'package:material_ui/material_ui.dart';

void showDatabaseQuarantineBanner(BuildContext context) {
  if (!hasDatabaseQuarantineNotice) return;
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  scaffoldMessenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: colorScheme.errorContainer,
      contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onErrorContainer,
      ),
      leading: Icon(
        Icons.warning_amber_rounded,
        color: colorScheme.onErrorContainer,
      ),
      content: Text(l10n.databaseQuarantined),
      actions: [
        TextButton(
          onPressed: () {
            dismissDatabaseQuarantineNotice();
            scaffoldMessenger.hideCurrentMaterialBanner();
          },
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
