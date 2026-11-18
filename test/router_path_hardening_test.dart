// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Uri location() => FluffyChatApp.router.routeInformationProvider.value.uri;

  testWidgets('a path with an authority or backslash never becomes the route', (
    tester,
  ) async {
    await harness.open(tester, path: '/rooms');
    for (final target in [
      '//evil.example/x',
      '//evil.example',
      '/rooms/..//evil.example',
      r'/\evil.example',
      r'/rooms/\evil.example',
      r'/\\evil.example/x',
    ]) {
      FluffyChatApp.router.go(target);
      await tester.pump(const Duration(milliseconds: 200));
      final uri = location();
      expect(uri.host, isEmpty, reason: target);
      expect(uri.path.startsWith('//'), isFalse, reason: target);
      expect(uri.path.contains(r'\'), isFalse, reason: target);
      expect(uri.toString().contains('evil.example'), isFalse, reason: target);
    }
    await harness.finish(tester);
  });

  testWidgets('ordinary room and settings paths are untouched', (tester) async {
    await harness.open(tester, path: '/rooms');
    FluffyChatApp.router.go('/settings');
    await tester.pump(const Duration(milliseconds: 200));
    expect(location().path, '/settings');
    await harness.finish(tester);
  });
}
