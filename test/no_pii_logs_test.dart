// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';
import 'utils/test_client.dart';

void main() {
  final harness = ChatPageHarness();

  late Client stranger;

  setUpAll(() async {
    await harness.setUpAll();
    stranger = await prepareTestClient(
      clientName: 's2stranger',
      loggedIn: true,
    );
  });
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  String logged() => Logs().outputEvents
      .map((event) => '${event.title} ${event.exception}')
      .join('\n');

  testWidgets('an unknown account switch does not log the account id', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms');
    final accountId = stranger.userID!;
    Logs().outputEvents.clear();
    tester.state<MatrixState>(find.byType(Matrix)).setActiveClient(stranger);
    expect(logged(), isNot(contains(accountId)));
    expect(logged(), contains('unknown client'));
    await harness.finish(tester);
  });

  testWidgets('a shared content uri is not written to the log', (tester) async {
    await harness.open(tester, path: '/rooms');
    Logs().outputEvents.clear();
    FluffyChatApp.router.go('content://s2canary.provider/secret-file');
    await tester.pump(const Duration(milliseconds: 200));
    expect(logged(), isNot(contains('s2canary')));
    expect(logged(), isNot(contains('secret-file')));
    await harness.finish(tester);
  });
}
