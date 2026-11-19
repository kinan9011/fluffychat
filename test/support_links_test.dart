// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/branding/support_links.dart';

void main() {
  test('empty settings give no links', () {
    final links = SupportLinks.from(koFi: '', buyMeACoffee: '');
    expect(links.koFi, isNull);
    expect(links.buyMeACoffee, isNull);
    expect(links.hasAny, isFalse);
  });

  test('https links with a host are accepted', () {
    final links = SupportLinks.from(
      koFi: 'https://ko-fi.com/example',
      buyMeACoffee: 'https://buymeacoffee.com/example',
    );
    expect(links.koFi.toString(), 'https://ko-fi.com/example');
    expect(links.buyMeACoffee.toString(), 'https://buymeacoffee.com/example');
    expect(links.hasAny, isTrue);
  });

  test('one link alone is enough', () {
    final links = SupportLinks.from(
      koFi: 'https://ko-fi.com/example',
      buyMeACoffee: '',
    );
    expect(links.hasAny, isTrue);
    expect(links.buyMeACoffee, isNull);
  });

  test('anything but a plain https link is dropped', () {
    for (final url in [
      'http://ko-fi.com/example',
      'javascript:alert(1)',
      'intent://scan/#Intent;scheme=zxing;end',
      'file:///etc/passwd',
      'mailto:a@example.org',
      'https://user:pw@ko-fi.com/example',
      'https://',
      'ko-fi.com/example',
      'https://${'a' * 3000}.example',
      ' https://ko-fi.com/example',
    ]) {
      final links = SupportLinks.from(koFi: url, buyMeACoffee: url);
      expect(links.koFi, isNull, reason: url);
      expect(links.buyMeACoffee, isNull, reason: url);
    }
  });

  test('isAcceptableSupportUrl allows empty and https only', () {
    expect(isAcceptableSupportUrl(''), isTrue);
    expect(isAcceptableSupportUrl('https://ko-fi.com/x'), isTrue);
    expect(isAcceptableSupportUrl('http://ko-fi.com/x'), isFalse);
    expect(isAcceptableSupportUrl(5), isFalse);
    expect(isAcceptableSupportUrl(null), isFalse);
  });
}
