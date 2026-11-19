// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/push_gateway_policy.dart';

void main() {
  test('this build ships without a push gateway', () {
    expect(AppSettings.pushNotificationsGatewayUrl.defaultValue, '');
    expect(
      resolvePushGateway(AppSettings.pushNotificationsGatewayUrl.defaultValue),
      isNull,
    );
  });

  test('a configured https gateway is used as is', () {
    expect(
      resolvePushGateway('https://push.example.org/_matrix/push/v1/notify'),
      'https://push.example.org/_matrix/push/v1/notify',
    );
  });

  test('anything else disables push', () {
    for (final url in [
      '',
      ' ',
      'http://push.example.org/_matrix/push/v1/notify',
      'https://',
      'https:///_matrix/push/v1/notify',
      'https://user:pw@push.example.org/_matrix/push/v1/notify',
      'https://push.example.org',
      'javascript:alert(1)',
      'push.example.org/_matrix/push/v1/notify',
    ]) {
      expect(resolvePushGateway(url), isNull, reason: url);
    }
  });

  test('the upstream gateway is never a default', () {
    expect(
      AppSettings.pushNotificationsGatewayUrl.defaultValue,
      isNot(contains('fluffychat')),
    );
  });
}
