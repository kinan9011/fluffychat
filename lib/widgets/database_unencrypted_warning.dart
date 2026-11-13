// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DatabaseUnencryptedWarningTile extends StatelessWidget {
  const DatabaseUnencryptedWarningTile({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    return ListTile(
      tileColor: colorScheme.errorContainer,
      textColor: colorScheme.onErrorContainer,
      iconColor: colorScheme.onErrorContainer,
      leading: const Icon(Icons.lock_open_outlined),
      title: Text(l10n.databaseNotEncrypted),
      subtitle: Text(l10n.databaseNotEncryptedDescription),
    );
  }
}

void showDatabaseUnencryptedBanner(BuildContext context) {
  if (!isDatabaseUnencrypted ||
      AppSettings.databaseUnencryptedNoticeDismissed.value) {
    return;
  }
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
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
        Icons.lock_open_outlined,
        color: colorScheme.onErrorContainer,
      ),
      content: Text(l10n.databaseNotEncrypted),
      actions: [
        TextButton(
          onPressed: () {
            AppSettings.databaseUnencryptedNoticeDismissed.setItem(true);
            scaffoldMessenger.hideCurrentMaterialBanner();
          },
          child: Text(l10n.close),
        ),
        TextButton(
          onPressed: () {
            scaffoldMessenger.hideCurrentMaterialBanner();
            router.go('/settings/security');
          },
          child: Text(l10n.security),
        ),
      ],
    ),
  );
}
