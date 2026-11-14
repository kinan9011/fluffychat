// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/shell_banner.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

@visibleForTesting
String databaseUnencryptedDescription(
  L10n l10n, {
  bool isWeb = kIsWeb,
  bool? isLinux,
}) {
  if (isWeb) return l10n.databaseNotEncryptedWeb;
  final hint = (isLinux ?? PlatformInfos.isLinux)
      ? l10n.databaseNotEncryptedKeyringHint
      : l10n.databaseNotEncryptedRestartHint;
  return '${l10n.databaseNotEncryptedDescription} $hint';
}

class DatabaseUnencryptedWarningTile extends StatelessWidget {
  @visibleForTesting
  final bool? isLinux;

  const DatabaseUnencryptedWarningTile({super.key, this.isLinux});

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
      subtitle: Text(databaseUnencryptedDescription(l10n, isLinux: isLinux)),
    );
  }
}

class DatabaseUnencryptedBanner extends StatelessWidget {
  final Widget child;

  const DatabaseUnencryptedBanner({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ShellBanner(
      isVisible: () =>
          isDatabaseUnencrypted &&
          !AppSettings.databaseUnencryptedNoticeDismissed.value,
      icon: Icons.lock_open_outlined,
      message: l10n.databaseNotEncrypted,
      actions: (hide) => [
        TextButton(
          onPressed: () {
            AppSettings.databaseUnencryptedNoticeDismissed.setItem(true);
            hide();
          },
          child: Text(l10n.close),
        ),
        TextButton(
          onPressed: () {
            hide();
            GoRouter.of(context).go('/settings/security');
          },
          child: Text(l10n.security),
        ),
      ],
      child: child,
    );
  }
}
