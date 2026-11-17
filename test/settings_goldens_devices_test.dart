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

  int at(int day) => DateTime.utc(2024, 6, day, 12).millisecondsSinceEpoch;

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.getOverrides.clear();
    api.notFound.clear();
    await (harness.client.database as MatrixSdkDatabase)
        .clearCustomCacheObjects();
    api.getOverrides['/devices'] = {
      'devices': [
        {
          'device_id': 'ABCD1234',
          'display_name': 'Pixel 8 · Android',
          'last_seen_ts': at(15),
        },
        {
          'device_id': 'OTHER1',
          'display_name': 'FluffyChat Linux',
          'last_seen_ts': at(14),
        },
        {
          'device_id': 'OTHER2',
          'display_name': 'Firefox on Windows',
          'last_seen_ts': at(10),
        },
        {'device_id': 'OTHER3', 'display_name': 'Galaxy Tab S9'},
      ],
    };
    api.getOverrides['/versions'] = {
      'versions': ['v1.1'],
      'unstable_features': {'org.matrix.msc4108': true},
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
      path: '/settings/devices',
      brightness: brightness,
      locale: locale,
    );
    await harness.settle(tester, rounds: 8);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_devices_$suffix.png'),
    );
    await harness.finish(tester);
  }

  testWidgets('linked devices light', (tester) async {
    await shot(tester, 'light');
  });

  testWidgets('linked devices dark', (tester) async {
    await shot(tester, 'dark', brightness: Brightness.dark);
  });
}
