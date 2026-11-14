// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/database_unencrypted_warning.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/golden.dart';

void main() {
  testGoldens('DatabaseUnencryptedWarningTile', (tester) async {
    await expectGoldenVariants(
      tester,
      'database_unencrypted_warning_tile',
      const DatabaseUnencryptedWarningTile(isLinux: true),
      size: const Size(400, 160),
    );
  });
}
