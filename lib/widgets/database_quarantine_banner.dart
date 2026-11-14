// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_quarantine_notice.dart';
import 'package:fluffychat/widgets/shell_banner.dart';
import 'package:material_ui/material_ui.dart';

class DatabaseQuarantineBanner extends StatelessWidget {
  final Widget child;

  const DatabaseQuarantineBanner({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ShellBanner(
      isVisible: () => hasDatabaseQuarantineNotice,
      icon: Icons.warning_amber_rounded,
      message: l10n.databaseQuarantined,
      actions: (hide) => [
        TextButton(
          onPressed: () {
            dismissDatabaseQuarantineNotice();
            hide();
          },
          child: Text(l10n.close),
        ),
      ],
      child: child,
    );
  }
}
