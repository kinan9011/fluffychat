// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

Future<Color> avatarFill(WidgetTester tester, Avatar avatar) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: avatar)));
  await tester.pump();
  final box = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(Avatar),
          matching: find.byType(Container),
        ),
      )
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .first;
  return box.color!;
}

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  testWidgets(
    'fallback avatar is filled from the name hash with white initials',
    (tester) async {
      final fill = await avatarFill(
        tester,
        Avatar(name: 'Anna Kim', client: client),
      );
      expect(fill, 'Anna Kim'.avatarColor);
      final text = tester.widgetList<Text>(find.text('AK')).first;
      expect(text.style!.color, Colors.white);
      expect(text.style!.fontFamily, 'JetBrainsMono');
    },
  );

  testWidgets('same name gives the same colour, the user id wins when given', (
    tester,
  ) async {
    final first = await avatarFill(
      tester,
      Avatar(name: 'Anna Kim', client: client),
    );
    final second = await avatarFill(
      tester,
      Avatar(name: 'Anna Kim', client: client),
    );
    expect(first, second);
    final byId = await avatarFill(
      tester,
      Avatar(
        name: 'Anna Kim',
        client: client,
        presenceUserId: '@anna:example.org',
      ),
    );
    expect(byId, '@anna:example.org'.avatarColor);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('explicit colours still override the generated ones', (
    tester,
  ) async {
    final fill = await avatarFill(
      tester,
      Avatar(
        name: 'Anna Kim',
        client: client,
        backgroundColor: Colors.black,
        textColor: Colors.red,
      ),
    );
    expect(fill, Colors.black);
    expect(
      tester.widgetList<Text>(find.text('AK')).first.style!.color,
      Colors.red,
    );
  });

  testWidgets('colorSeed (the Matrix ID) beats presenceUserId and the name', (
    tester,
  ) async {
    final renamed = await avatarFill(
      tester,
      Avatar(name: 'Anna Kim', client: client, colorSeed: '@anna:example.org'),
    );
    final other = await avatarFill(
      tester,
      Avatar(
        name: 'Completely Different',
        client: client,
        colorSeed: '@anna:example.org',
      ),
    );
    expect(renamed, '@anna:example.org'.avatarColor);
    expect(other, renamed);
    final both = await avatarFill(
      tester,
      Avatar(
        name: 'Anna Kim',
        client: client,
        colorSeed: '@anna:example.org',
        presenceUserId: '@someone:example.org',
      ),
    );
    expect(both, '@anna:example.org'.avatarColor);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  test('a group room is coloured by its id, a DM by the partner', () async {
    final room = client.rooms.first;
    expect(room.directChatMatrixID, isNull);
    expect(room.avatarColorSeed, room.id);
  });
}
