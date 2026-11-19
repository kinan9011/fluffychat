// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/backup_dump_validator.dart';
import 'package:odango/utils/localized_exception_extension.dart';

void main() {
  testWidgets('a failed import is not reported as an invalid file', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10n.of(context);

    final failed = const BackupRestoreFailedException().toLocalizedString(
      context,
    );
    expect(failed, l10n.backupRestoreFailed);
    expect(failed, startsWith('The backup could not be restored.'));
    expect(failed, isNot(l10n.backupFileInvalid));
    expect(
      const InvalidBackupException().toLocalizedString(context),
      l10n.backupFileInvalid,
    );
  });
}
