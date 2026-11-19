// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/widgets/shell_banner.dart';

import 'utils/golden.dart';

void main() {
  testWidgets('a shell banner is announced when it appears', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(
      tester,
      ShellBanner(
        isVisible: () => true,
        icon: Icons.warning_rounded,
        message: 'Your database is not encrypted',
        actions: (hide) => [
          TextButton(onPressed: hide, child: const Text('OK')),
        ],
        child: const SizedBox(),
      ),
    );
    final node = tester.getSemantics(
      find.textContaining('Your database is not encrypted'),
    );
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
