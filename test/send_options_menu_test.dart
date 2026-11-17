// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/pages/chat/scheduling/send_options_menu.dart';
import 'package:fluffychat/utils/scheduling/send_options.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/golden.dart';

const _anchor = Rect.fromLTWH(332, 230, 52, 52);
const _anchorRtl = Rect.fromLTWH(16, 230, 52, 52);

Future<SendOption?> open(
  WidgetTester tester, {
  List<SendOption> options = const [SendOption.silent, SendOption.schedule],
  String? partnerName,
  Rect anchor = _anchor,
}) {
  final context = tester.element(find.byType(Scaffold));
  return showSendOptionsMenu(
    context,
    options: options,
    anchor: anchor,
    partnerName: partnerName,
  );
}

/// A locale other than the first one loads its date data asynchronously.
Future<void> localeReady(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget get _page => const SizedBox.expand();

void main() {
  testWidgets('shows the offered options with their labels', (tester) async {
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    unawaited(open(tester, options: SendOption.values, partnerName: 'Mara'));
    await settle(tester);
    expect(find.text('Send without sound'), findsOneWidget);
    expect(find.text('Schedule message'), findsOneWidget);
    expect(find.text('Send when Mara is online'), findsOneWidget);
    expect(find.byType(GlassMenuRow), findsNWidgets(3));
  });

  testWidgets('without when online only two rows', (tester) async {
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    unawaited(open(tester));
    await settle(tester);
    expect(find.byType(GlassMenuRow), findsNWidgets(2));
    expect(find.textContaining('online'), findsNothing);
  });

  testWidgets('the best effort note shows with the silent option only', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    unawaited(open(tester));
    await settle(tester);
    expect(find.textContaining('best effort'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    unawaited(open(tester, options: const [SendOption.schedule]));
    await settle(tester);
    expect(find.textContaining('best effort'), findsNothing);
  });

  testWidgets('a tap returns that option', (tester) async {
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    final result = open(tester);
    await settle(tester);
    await tester.tap(find.text('Schedule message'));
    await tester.pumpAndSettle();
    expect(await result, SendOption.schedule);
  });

  testWidgets('escape and a tap outside return null', (tester) async {
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    var result = open(tester);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await result, isNull);
    result = open(tester);
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('rows are 50 high and the card sits above the button', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    unawaited(open(tester));
    await settle(tester);
    for (final row in tester.widgetList(find.byType(GlassMenuRow)).indexed) {
      final size = tester.getSize(find.byType(GlassMenuRow).at(row.$1));
      expect(size.height, greaterThanOrEqualTo(AppSchedule.menuRow));
    }
    final card = tester.getRect(find.byType(GlassMenuCard));
    expect(card.width, AppSchedule.menuWidth);
    expect(card.bottom, closeTo(_anchor.top - AppSchedule.menuGap, 0.5));
    expect(card.right, closeTo(_anchor.right, 0.5));
  });

  testWidgets('rows carry their label for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(tester, _page, size: const Size(400, 300));
    unawaited(open(tester));
    await settle(tester);
    expect(find.bySemanticsLabel('Schedule message'), findsWidgets);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Schedule message').first),
      matchesSemantics(
        label: 'Schedule message',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('goldens', (tester) async {
    for (final variant in goldenVariants) {
      final anchor = variant.rtl ? _anchorRtl : _anchor;
      await pumpGoldenWidget(
        tester,
        Stack(
          children: [
            Positioned.fromRect(
              rect: anchor,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF5B5BD6),
                ),
              ),
            ),
          ],
        ),
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: variant.locale,
        size: const Size(400, 300),
      );
      await localeReady(tester);
      unawaited(
        open(
          tester,
          options: SendOption.values,
          partnerName: 'Mara',
          anchor: anchor,
        ),
      );
      await settle(tester);
      final card = tester.getRect(find.byType(GlassMenuCard));
      expect(
        variant.rtl ? card.left : card.right,
        closeTo(variant.rtl ? anchor.left : anchor.right, 0.5),
        reason: 'the card hangs from the button edge (${variant.suffix})',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/send_options_menu_${variant.suffix}.png'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });
}
