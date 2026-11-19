// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

/// The Arabic delegate loads asynchronously and only the first test of a file
/// gets it reliably (m10), so every RTL golden of the conversation shell lives
/// in this one test.
void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    harness.capabilities.set(harness.client, supported: false);
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(() async {
    await harness.tearDown();
    await AppSettings.sendTypingNotifications.setItem(true);
  });

  testWidgets('header and composer mirror in RTL', (tester) async {
    await harness.open(tester, locale: const Locale('ar'));
    final header = tester.getTopLeft(
      find.byKey(const Key('chat_overflow_button')),
    );
    final composerAction = tester.getTopLeft(find.byType(ChatInputRow));
    expect(header.dx, lessThan(100), reason: 'overflow starts at the left');
    expect(composerAction.dx, lessThan(100));
    await tester.tap(find.byKey(const Key('chat_overflow_button')));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat_header_rtl.png'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 3);
    final controller = tester.state<ChatController>(
      find.byType(ChatPageWithRoom),
    );
    harness.room.ephemerals.remove('m.typing');
    controller.timeline!.events.insert(
      0,
      Event(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'hello there'},
        room: harness.room,
        eventId: r'$rtl:example.org',
        senderId: harness.client.userID!,
        originServerTs: DateTime(2030, 1, 1, 12, 41),
      ),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 3);
    await tester.longPress(find.text('hello there'));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(GlassMenuCard), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/message_menu_rtl.png'),
    );
    await harness.finish(tester);
  });
}
