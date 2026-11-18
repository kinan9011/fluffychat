// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    await DraftStore.of(harness.client).remove(harness.room.id);
    api.clear();
  });
  tearDown(harness.tearDown);

  String composerText(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('chat_input_field')),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  testWidgets('a room link with ?body= fills the composer and sends nothing', (
    tester,
  ) async {
    final path =
        '/rooms/${Uri.encodeComponent(harness.room.id)}?body=I%20resign';
    await harness.open(tester, path: path);
    await harness.settle(tester, rounds: 6);
    expect(api.requests('/send/', method: 'PUT'), isEmpty);
    expect(
      composerText(tester),
      'I resign',
      reason: 'the text waits in the composer for the user to press send',
    );
    await harness.finish(tester);
    expect(api.requests('/send/', method: 'PUT'), isEmpty);
  });

  testWidgets('a very long ?body= is cut to a draft-sized text', (
    tester,
  ) async {
    final long = 'a' * 20000;
    final path = '/rooms/${Uri.encodeComponent(harness.room.id)}?body=$long';
    await harness.open(tester, path: path);
    await harness.settle(tester, rounds: 6);
    expect(api.requests('/send/', method: 'PUT'), isEmpty);
    expect(composerText(tester).length, 8000);
    await harness.finish(tester);
  });
}
