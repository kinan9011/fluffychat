// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/themes.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/input_bar.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient());

  testWidgets('an emote with a malformed mxc uri is skipped, not a crash '
      '(SEC L6)', (tester) async {
    final bar = InputBar(
      room: Room(id: '!r:example.org', client: client),
      decoration: const InputDecoration(),
      suggestionEmojis: const [],
    );
    await pumpGoldenWidget(tester, const SizedBox());
    await tester.pumpWidget(
      Builder(
        builder: (context) => MaterialApp(
          theme: FluffyThemes.buildTheme(context, Brightness.light),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => bar.buildSuggestion(
                context,
                {
                  'type': 'emote',
                  'name': ':bad:',
                  'pack_display_name': 'Pack',
                  'mxc': 'mxc://host:xx/c',
                },
                (_) {},
                client,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(':bad:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
