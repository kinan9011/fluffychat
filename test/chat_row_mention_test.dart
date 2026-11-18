// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  Future<String> label(WidgetTester tester, int highlight) async {
    await pumpGoldenWidget(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: ChatListItem(
          testChat(
            client,
            '!mention:example.org',
            name: 'Mara',
            unread: 2,
            highlight: highlight,
            lastBody: 'see you',
          ),
          activeChat: false,
          onTap: () {},
        ),
      ),
      size: const Size(400, 600),
    );
    await tester.pump();
    return find.semantics.byLabel(RegExp('^Mara')).evaluate().single.label;
  }

  testWidgets('the row announces a mention to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    expect(await label(tester, 1), contains('Mention'));
    handle.dispose();
  });

  testWidgets('without a mention the word is not there', (tester) async {
    final handle = tester.ensureSemantics();
    expect(await label(tester, 0), isNot(contains('Mention')));
    handle.dispose();
  });
}
