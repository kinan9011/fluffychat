// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/config/setting_keys.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
  });
  tearDown(harness.tearDown);

  final input = find.byKey(const Key('chat_input_field'));

  for (final size in [const Size(400, 900), const Size(320, 480)]) {
    testWidgets(
      'typing off (default): no typing request, ${size.width.toInt()} wide',
      (tester) async {
        await harness.open(tester, width: size.width, height: size.height);
        api.clear();
        await tester.enterText(input, 'hello');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(input, 'hello world');
        await tester.pump(const Duration(seconds: 3));
        expect(api.requests('/typing/'), isEmpty);
        await harness.finish(tester);
        expect(api.requests('/typing/'), isEmpty);
      },
    );
  }

  testWidgets('typing on: one typing request while typing, one to stop', (
    tester,
  ) async {
    await AppSettings.sendTypingNotifications.setItem(true);
    await harness.open(tester);
    api.clear();
    await tester.enterText(input, 'hello');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(input, 'hello world');
    await tester.pump(const Duration(milliseconds: 100));
    final typing = api.requests('/typing/', method: 'PUT');
    expect(typing, hasLength(1));
    expect((typing.single.json! as Map)['typing'], isTrue);
    await tester.pump(const Duration(seconds: 3));
    final all = api.requests('/typing/', method: 'PUT');
    expect(all, hasLength(2));
    expect((all.last.json! as Map)['typing'], isFalse);
    await harness.finish(tester);
  });

  testWidgets('turned off while typing: one stop, no new typing', (
    tester,
  ) async {
    await AppSettings.sendTypingNotifications.setItem(true);
    await harness.open(tester);
    api.clear();
    await tester.enterText(input, 'hello');
    await tester.pump(const Duration(milliseconds: 100));
    await AppSettings.sendTypingNotifications.setItem(false);
    await tester.enterText(input, 'hello again');
    await tester.pump(const Duration(milliseconds: 100));
    final typing = api.requests('/typing/', method: 'PUT');
    expect(typing.map((r) => (r.json! as Map)['typing']), [true, false]);
    await tester.pump(const Duration(seconds: 3));
    expect(api.requests('/typing/', method: 'PUT'), hasLength(2));
    await harness.finish(tester);
  });
}
