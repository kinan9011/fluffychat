// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show MatrixSdkDatabase;

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    harness.capabilities.set(harness.client, supported: false);
    await AppSettings.store.clear();
    api.clear();
    api.getOverrides.clear();
    api.notFound.clear();
    await (harness.client.database as MatrixSdkDatabase)
        .clearCustomCacheObjects();
    api.getOverrides['/versions'] = {
      'versions': ['v1.1', 'v1.4'],
      'unstable_features': {
        'org.matrix.simplified_msc3575': true,
        'org.matrix.msc1763': false,
        'org.matrix.msc4140': false,
        'org.matrix.msc4108': true,
      },
    };
    api.getOverrides['/config'] = {'m.upload.size': 100000000};
    api.getOverrides['/matrix/server'] = {
      'm.server': 'federation.fakeserver.notexisting:8448',
    };
    api.getOverrides['/federation/v1/version'] = {
      'server': {'name': 'tuwunel', 'version': '1.4.0'},
    };
  });
  tearDown(harness.tearDown);

  Future<void> shot(
    WidgetTester tester,
    String suffix, {
    Brightness brightness = Brightness.light,
    Locale? locale,
  }) async {
    await harness.open(
      tester,
      path: '/settings/homeserver',
      brightness: brightness,
      locale: locale,
    );
    await harness.settle(tester, rounds: 8);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_homeserver_$suffix.png'),
    );
    await harness.finish(tester);
  }

  testWidgets('homeserver light', (tester) async {
    await shot(tester, 'light');
  });

  testWidgets('homeserver dark', (tester) async {
    await shot(tester, 'dark', brightness: Brightness.dark);
  });
}
