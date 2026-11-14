// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/launch_web_url.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isLaunchableWebUrl', () {
    for (final url in [
      'https://example.org/x',
      'HTTPS://EXAMPLE.ORG',
      'http://a.b:8448/',
    ]) {
      test('accepts $url', () => expect(isLaunchableWebUrl(url), isTrue));
    }
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'intent://x#Intent;end',
      'https://',
      '',
      'mailto:a@b.c',
      'matrix:r/x:y',
      r'C:\x.exe',
      'ms-settings:',
    ]) {
      test('rejects "$url"', () => expect(isLaunchableWebUrl(url), isFalse));
    }
  });

  test('launchWebUrl refuses a non-web url without launching', () async {
    final launched = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
            }
            return true;
          },
        );
    expect(await launchWebUrl('intent://x'), isFalse);
    expect(launched, isEmpty);
    expect(await launchWebUrl('https://example.org/ok'), isTrue);
    expect(launched, ['https://example.org/ok']);
  });
}
