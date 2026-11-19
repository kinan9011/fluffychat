// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/pages/chat/chat.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> receive(
    WidgetTester tester,
    String body,
    String formatted,
    String id,
  ) async {
    final controller = tester.state<ChatController>(
      find.byType(ChatPageWithRoom),
    );
    controller.timeline!.events.insert(
      0,
      Event(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Text,
          'body': body,
          'format': 'org.matrix.custom.html',
          'formatted_body': formatted,
        },
        room: harness.room,
        eventId: id,
        senderId: '@someone:example.org',
        originServerTs: DateTime.now(),
      ),
    );
    controller.updateView();
    await harness.settle(tester, rounds: 3);
  }

  testWidgets('an over-long formatted body is shown as its plain body', (
    tester,
  ) async {
    await harness.open(tester);
    await receive(
      tester,
      'plain-fallback-text',
      '<b>FORMATTED-ONLY</b>${'<div>' * 8000}x${'</div>' * 8000}',
      r'$long:example.org',
    );
    expect(find.textContaining('plain-fallback-text'), findsOneWidget);
    expect(
      find.textContaining('FORMATTED-ONLY', findRichText: true),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  testWidgets('a normal formatted body still renders its markup', (
    tester,
  ) async {
    await harness.open(tester);
    await receive(
      tester,
      'plain-fallback-text',
      '<b>FORMATTED-ONLY</b>',
      r'$short:example.org',
    );
    expect(
      find.textContaining('FORMATTED-ONLY', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('plain-fallback-text'), findsNothing);
    await harness.finish(tester);
  });
}
