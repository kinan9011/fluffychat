// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/support/support_dialog.dart';
import 'package:odango/utils/branding/support_links.dart';

import 'utils/golden.dart';

void main() {
  final bothLinks = SupportLinks.from(
    koFi: 'https://ko-fi.com/example',
    buyMeACoffee: 'https://buymeacoffee.com/example',
  );

  testWidgets('buttons carry their text as the screen reader label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpGoldenWidget(tester, const SizedBox());
    await pumpGoldenWidget(
      tester,
      Center(child: SupportDialog(links: bothLinks)),
      size: const Size(400, 700),
    );
    await tester.pumpAndSettle();
    for (final label in ['Support on Ko-fi', 'Buy me a coffee', 'Close']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      final node = tester.getSemantics(button);
      expect(node.label, label);
      expect(node.flagsCollection.isButton, isTrue);
    }
    semantics.dispose();
  });
}
