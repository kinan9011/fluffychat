// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

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

  testWidgets('composer keeps its keys and swaps mic for send', (tester) async {
    await harness.open(tester);
    expect(find.byKey(const Key('chat_input_field')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatInputRow),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('chat_input_field')), 'hello');
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('send_button')), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('no schedule shortcut before W06', (tester) async {
    await harness.open(tester);
    expect(find.byIcon(Icons.schedule_send_rounded), findsNothing);
    expect(find.byIcon(Icons.schedule_send_outlined), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('the action button is a 52 px accent circle', (tester) async {
    await harness.open(tester);
    await tester.enterText(find.byKey(const Key('chat_input_field')), 'x');
    await harness.settle(tester, rounds: 2);
    final size = tester.getSize(find.byKey(const Key('send_button')));
    expect(size, const Size.square(52));
    await harness.finish(tester);
  });

  for (final (brightness, suffix, locale) in [
    (Brightness.light, 'light', const Locale('en')),
    (Brightness.dark, 'dark', const Locale('en')),
  ]) {
    testWidgets('golden $suffix', (tester) async {
      await harness.open(tester, brightness: brightness, locale: locale);
      await expectLater(
        find.byType(ChatInputRow),
        matchesGoldenFile('goldens/chat_composer_$suffix.png'),
      );
      await harness.finish(tester);
    });
  }

  testWidgets('the not-logged-in note sits on a glass pill (REV m16)', (
    tester,
  ) async {
    final room = harness.room;
    final saved = <String, Map<String, DeviceKeys>>{};
    for (final user in room.getParticipants()) {
      final keys = harness.client.userDeviceKeys[user.id];
      if (keys == null || user.id == harness.client.userID) continue;
      saved[user.id] = Map.of(keys.deviceKeys);
      keys.deviceKeys.clear();
    }
    addTearDown(() {
      for (final entry in saved.entries) {
        harness.client.userDeviceKeys[entry.key]!.deviceKeys.addAll(
          entry.value,
        );
      }
    });
    await harness.open(tester);
    final note = find.text(
      'The other party is currently not logged in and therefore cannot '
      'receive messages!',
    );
    expect(note, findsOneWidget);
    expect(
      find.ancestor(of: note, matching: find.byType(GlassSurface)),
      findsOneWidget,
    );
    await harness.finish(tester);
  });
}
