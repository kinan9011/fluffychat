// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/chat/chat_jump_buttons.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  setUpAll(prepareTestClient);

  Widget buttons({
    int mention = 0,
    int unread = 0,
    bool scrollDown = true,
    VoidCallback? onMention,
    VoidCallback? onScrollDown,
  }) => Align(
    alignment: AlignmentDirectional.bottomEnd,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: ChatJumpButtons(
        mentionCount: mention,
        unreadCount: unread,
        showScrollDown: scrollDown,
        onMention: onMention ?? () {},
        onScrollDown: onScrollDown ?? () {},
      ),
    ),
  );

  testWidgets('badges show the count and cap at 99+', (tester) async {
    await pumpGoldenWidget(tester, buttons(mention: 2, unread: 120));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('zero counts hide the badges and the mention button', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, buttons());
    expect(find.byKey(ChatJumpButtons.mentionKey), findsNothing);
    expect(find.byKey(ChatJumpButtons.scrollDownKey), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the scroll button is hidden when not scrolled up', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, buttons(mention: 1, scrollDown: false));
    expect(find.byKey(ChatJumpButtons.scrollDownKey), findsNothing);
    expect(find.byKey(ChatJumpButtons.mentionKey), findsOneWidget);
  });

  testWidgets('taps reach the callbacks and targets are at least 44 px', (
    tester,
  ) async {
    var mention = 0;
    var down = 0;
    await pumpGoldenWidget(
      tester,
      buttons(
        mention: 1,
        unread: 3,
        onMention: () => mention++,
        onScrollDown: () => down++,
      ),
    );
    for (final key in [
      ChatJumpButtons.mentionKey,
      ChatJumpButtons.scrollDownKey,
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    await tester.tap(find.byKey(ChatJumpButtons.mentionKey));
    await tester.tap(find.byKey(ChatJumpButtons.scrollDownKey));
    expect([mention, down], [1, 1]);
  });

  testWidgets('semantics labels carry the counts', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGoldenWidget(tester, buttons(mention: 2, unread: 5));
    expect(find.bySemanticsLabel('Jump to mention, 2 unread'), findsOneWidget);
    expect(find.bySemanticsLabel('Scroll to bottom, 5 unread'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('goldens in light, dark and RTL', (tester) async {
    for (final variant in goldenVariants) {
      await pumpGoldenWidget(
        tester,
        buttons(mention: 2, unread: 12),
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: variant.locale,
        size: const Size(200, 220),
      );
      if (variant.rtl) {
        final x = tester.getTopLeft(find.byKey(ChatJumpButtons.mentionKey)).dx;
        expect(x, lessThan(100));
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/chat_jump_buttons_${variant.suffix}.png'),
      );
    }
  });
}
