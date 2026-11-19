// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test('bool setItem bumps the listenable by one', () async {
    final before = AppSettings.reduceTransparency.listenable.value;
    await AppSettings.reduceTransparency.setItem(true);
    expect(AppSettings.reduceTransparency.listenable.value, before + 1);
  });

  test('string setItem bumps the listenable', () async {
    final before = AppSettings.chatFilter.listenable.value;
    await AppSettings.chatFilter.setItem('x');
    expect(AppSettings.chatFilter.listenable.value, before + 1);
  });

  test('int, double and list setItem bump the listenable', () async {
    final accent = AppSettings.accentHue.listenable.value;
    final font = AppSettings.fontSizeFactor.listenable.value;
    final hashes = AppSettings.knownErrorHashes.listenable.value;
    await AppSettings.accentHue.setItem(120);
    await AppSettings.fontSizeFactor.setItem(1.2);
    await AppSettings.knownErrorHashes.setItem(['a']);
    expect(AppSettings.accentHue.listenable.value, accent + 1);
    expect(AppSettings.fontSizeFactor.listenable.value, font + 1);
    expect(AppSettings.knownErrorHashes.listenable.value, hashes + 1);
  });

  test('nullable bool setItem bumps the listenable', () async {
    final before = AppSettings.autoSendErrorReports.listenable.value;
    await AppSettings.autoSendErrorReports.setItem(true);
    expect(AppSettings.autoSendErrorReports.listenable.value, before + 1);
  });

  test('different settings have independent notifiers', () async {
    final other = AppSettings.hideRoomsInSpaces.listenable.value;
    await AppSettings.reduceTransparency.setItem(true);
    expect(AppSettings.hideRoomsInSpaces.listenable.value, other);
  });

  test('reset bumps every setting', () async {
    final before = AppSettings.reduceTransparency.listenable.value;
    final other = AppSettings.chatFilter.listenable.value;
    await AppSettings.reset(loadWebConfigFile: false);
    expect(
      AppSettings.reduceTransparency.listenable.value,
      greaterThan(before),
    );
    expect(AppSettings.chatFilter.listenable.value, greaterThan(other));
  });

  test('notifyRemoved bumps the listenable', () {
    final before = AppSettings.accentHue.listenable.value;
    AppSettings.accentHue.notifyRemoved();
    expect(AppSettings.accentHue.listenable.value, before + 1);
  });
}
