// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/branding/docs_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.reset(loadWebConfigFile: false);
  });

  test('help pages are derived from the website of the app', () {
    expect(
      docsUrl(DocsPage.push).toString(),
      'https://odango.swovo.de/docs/push',
    );
    expect(
      docsUrl(DocsPage.encryption).toString(),
      'https://odango.swovo.de/docs/encryption',
    );
    expect(
      docsUrl(DocsPage.stickers).toString(),
      'https://odango.swovo.de/docs/stickers',
    );
  });

  test('a configured website moves the help pages with it', () async {
    await AppSettings.website.setItem('https://chat.example.org/ignored?x=1');
    expect(
      docsUrl(DocsPage.push).toString(),
      'https://chat.example.org/docs/push',
    );
  });

  test('no help button of the app opens a page of another project', () {
    for (final path in [
      'lib/utils/background_push.dart',
      'lib/pages/chat/sticker_picker_dialog.dart',
      'lib/pages/chat_encryption_settings/chat_encryption_settings_view.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('docsUrl(DocsPage.'), reason: path);
      expect(source, isNot(contains('upstream')), reason: path);
      expect(source, isNot(contains('ko-fi')), reason: path);
    }
  });
}
