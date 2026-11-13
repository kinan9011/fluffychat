// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/golden.dart';
import 'utils/space_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  Room space(List<String> children) => testSpace(client, children);

  Room child(String id, {int unread = 0, Membership? membership}) =>
      testSpaceChild(client, id, unread: unread, membership: membership);

  Future<void> pumpBubble(WidgetTester tester, Room space) =>
      pumpGoldenWidget(tester, SpaceUnreadBubble(space: space));

  setUp(() => client.rooms.clear());

  testWidgets('counts unread and invited chats of the space only', (
    tester,
  ) async {
    final s = space(['!a:x', '!b:x', '!c:x', '!d:x']);
    client.rooms.addAll([
      s,
      child('!a:x', unread: 3),
      child('!b:x'),
      child('!c:x', membership: Membership.invite),
      child('!elsewhere:x', unread: 9),
    ]);
    await pumpBubble(tester, s);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows nothing when everything is read', (tester) async {
    final s = space(['!a:x']);
    client.rooms.addAll([s, child('!a:x')]);
    await pumpBubble(tester, s);
    expect(find.byType(SpaceUnreadBubble), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });

  testWidgets('a space without children shows nothing', (tester) async {
    final s = space([]);
    client.rooms.add(s);
    await pumpBubble(tester, s);
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });
}
