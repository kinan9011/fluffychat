// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Needs a fresh isolate: `AppSettings.init` returns early once the store is set.
void main() {
  test('the first init migrates a legacy primary_color to accentHue', () async {
    SharedPreferences.setMockInitialValues({'primary_color': 0xFFF44336});

    final store = await AppSettings.init(loadWebConfigFile: false);

    expect(store.getInt(AppSettings.accentHue.key), 29);
    expect(store.containsKey('primary_color'), isFalse);
  });
}
