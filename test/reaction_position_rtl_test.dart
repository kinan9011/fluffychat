// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/reaction_pills.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';
import 'utils/reaction_fixtures.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(() async {
    await harness.tearDown();
    await AppSettings.sendTypingNotifications.setItem(true);
  });

  // ponytail: the Arabic l10n library only loads reliably in a file of its own.
  for (final size in [const Size(360, 640), const Size(1200, 900)]) {
    for (final (name, sender, text) in [
      ('incoming', otherSender, 'المهم مقطع'),
      ('outgoing', ownSender, 'المهم مقطع'),
      ('incoming latin text', otherSender, 'Hello there'),
      ('outgoing latin text', ownSender, 'Hello there'),
    ]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} $name: the chip is at the '
        'bubble edge and mirrors',
        (tester) async {
          await harness.open(
            tester,
            width: size.width,
            height: size.height,
            locale: const Locale('ar'),
          );
          final message = fixtureMessage(
            harness.room,
            sender: sender,
            text: text,
          );
          await showMessages(
            tester,
            harness,
            [message],
            [fixtureReaction(harness.room, message, '👍')],
          );
          expectChipAttached(
            bubbleRectOf(tester, message),
            chipRect(tester, '👍'),
            atStart: sender == otherSender,
            direction: TextDirection.rtl,
            reason: name,
          );
          await harness.finish(tester);
        },
      );
    }
  }

  for (final (name, sender) in [
    ('incoming', otherSender),
    ('outgoing', ownSender),
  ]) {
    testWidgets('$name: the +N label of hidden keys mirrors with the bubble', (
      tester,
    ) async {
      await harness.open(tester, locale: const Locale('ar'));
      final message = fixtureMessage(harness.room, sender: sender);
      await showMessages(
        tester,
        harness,
        [message],
        [
          for (var i = 0; i < 30; i++)
            fixtureReaction(harness.room, message, 'k$i'),
        ],
      );
      expectMoreAtSide(
        tester.getRect(find.byType(ReactionPills)),
        moreRect(tester),
        reason: name,
      );
      await harness.finish(tester);
    });
  }
}
