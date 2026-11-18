// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_live_kit_calls/livekit_service_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeLiveKitServiceUri', () {
    test('accepts https and strips trailing slashes', () {
      expect(
        safeLiveKitServiceUri('https://lk.example.org///')?.toString(),
        'https://lk.example.org',
      );
      expect(
        safeLiveKitServiceUri('https://lk.example.org/rtc')?.toString(),
        'https://lk.example.org/rtc',
      );
    });

    test('plain http only for the local machine', () {
      expect(safeLiveKitServiceUri('http://localhost:7880'), isNotNull);
      expect(safeLiveKitServiceUri('http://127.0.0.1:7880'), isNotNull);
      expect(safeLiveKitServiceUri('http://[::1]:7880'), isNotNull);
      expect(safeLiveKitServiceUri('http://lk.example.org'), isNull);
      expect(safeLiveKitServiceUri('http://192.168.1.5:7880'), isNull);
      expect(safeLiveKitServiceUri('http://127.0.0.1.evil.example'), isNull);
    });

    test('refuses every other scheme', () {
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'ftp://lk.example.org',
        'intent://lk.example.org#Intent;end',
        'content://lk',
        'data:text/plain,x',
        'ws://lk.example.org',
      ]) {
        expect(safeLiveKitServiceUri(url), isNull, reason: url);
      }
    });

    test('refuses userinfo, empty host and relative or empty input', () {
      for (final url in [
        'http://user:pw@lk.example.org',
        'https://user@lk.example.org',
        'https:///path',
        'https://',
        '//lk.example.org',
        'lk.example.org',
        '',
        '   ',
      ]) {
        expect(safeLiveKitServiceUri(url), isNull, reason: url);
      }
    });

    test('refuses unparsable and oversized input', () {
      expect(safeLiveKitServiceUri('https://exa mple.org:xx'), isNull);
      expect(
        safeLiveKitServiceUri('https://lk.example.org/${'a' * 4096}'),
        isNull,
      );
    });

    test('is case-insensitive about the scheme', () {
      expect(safeLiveKitServiceUri('HTTPS://lk.example.org'), isNotNull);
    });
  });
}
