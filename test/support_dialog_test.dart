// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_config.dart';
import 'package:odango/pages/support/support_dialog.dart';
import 'package:odango/utils/branding/support_links.dart';

import 'utils/golden.dart';

final _bothLinks = SupportLinks.from(
  koFi: 'https://ko-fi.com/example',
  buyMeACoffee: 'https://buymeacoffee.com/example',
);

bool _isFilledButton(Widget widget) => widget is FilledButton;

void main() {
  final launched = <String>[];
  Future<bool> launch(String url) async {
    launched.add(url);
    return true;
  }

  setUp(launched.clear);

  testWidgets('without donation links the dialog still explains and credits', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      const Center(child: SupportDialog()),
      size: const Size(400, 700),
    );
    expect(find.text('Support Odango'), findsOneWidget);
    expect(
      find.textContaining('part of what you give goes on to support'),
      findsOneWidget,
    );
    expect(find.textContaining('FluffyChat source it is built on'), findsOne);
    expect(find.text('Support on Ko-fi'), findsNothing);
    expect(find.text('Buy me a coffee'), findsNothing);
    expect(find.byWidgetPredicate(_isFilledButton), findsNothing);
    expect(
      find.text('No donation links are set up in this build.'),
      findsOneWidget,
    );
    expect(find.text('FluffyChat source code'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('a link that is set gets its own button and opens it', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      Center(
        child: SupportDialog(links: _bothLinks, launch: launch),
      ),
      size: const Size(400, 700),
    );
    expect(
      find.text('No donation links are set up in this build.'),
      findsNothing,
    );
    await tester.tap(find.text('Support on Ko-fi'));
    await tester.tap(find.text('Buy me a coffee'));
    await tester.tap(find.text('FluffyChat source code'));
    expect(launched, [
      'https://ko-fi.com/example',
      'https://buymeacoffee.com/example',
      AppConfig.upstreamRepoUrl,
    ]);
  });

  testWidgets('only the configured button is shown', (tester) async {
    await pumpGoldenWidget(
      tester,
      Center(
        child: SupportDialog(
          links: SupportLinks.from(
            koFi: '',
            buyMeACoffee: 'https://buymeacoffee.com/example',
          ),
          launch: launch,
        ),
      ),
      size: const Size(400, 700),
    );
    expect(find.text('Support on Ko-fi'), findsNothing);
    expect(find.text('Buy me a coffee'), findsOneWidget);
    expect(find.byWidgetPredicate(_isFilledButton), findsOneWidget);
  });

  testWidgets('a 320 px wide phone at double text size scrolls, no overflow', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: Center(child: SupportDialog(links: _bothLinks)),
        ),
      ),
      size: const Size(320, 480),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    for (final button in find.byWidgetPredicate(_isFilledButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(button.widget)).height,
        greaterThanOrEqualTo(44),
      );
    }
    final scrollable = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.text('Close'),
      scrollable,
      const Offset(0, -100),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('right to left mirrors without overflow', (tester) async {
    await pumpGoldenWidget(tester, const SizedBox());
    await pumpGoldenWidget(
      tester,
      Center(child: SupportDialog(links: _bothLinks)),
      rtl: true,
      locale: const Locale('ar'),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(SupportDialog))),
      TextDirection.rtl,
    );
    final koFi = tester.getRect(find.text('Support on Ko-fi'));
    expect(koFi.center.dx, closeTo(160, 40), reason: 'centred, not left bound');
  });

  testWidgets('goldens light, dark and right to left', (tester) async {
    await expectGoldenVariants(
      tester,
      'support_dialog',
      Center(child: SupportDialog(links: _bothLinks)),
      size: const Size(400, 700),
    );
  });
}
