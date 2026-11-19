// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/chat/new_device_banner_model.dart';

DeviceInfo _device(
  String id, {
  bool verified = false,
  bool blocked = false,
  bool signed = false,
  bool encrypt = true,
}) => DeviceInfo(
  id: id,
  verified: verified,
  blocked: blocked,
  signed: signed,
  encryptToDevice: encrypt,
);

NewDeviceBannerState? _eval(
  List<DeviceInfo> devices, {
  bool verified = true,
  Set<String> dismissed = const {},
  String account = '@me:example.org',
}) => evaluateNewDevices(
  accountId: account,
  partnerId: '@kim:example.org',
  partnerVerified: verified,
  devices: devices,
  dismissed: dismissed,
);

void main() {
  test('a partner you did not verify never shows the banner', () {
    expect(_eval([_device('A')], verified: false), isNull);
  });

  test('a verified partner with only signed devices shows nothing', () {
    expect(
      _eval([_device('A', signed: true), _device('B', verified: true)]),
      isNull,
    );
  });

  test('one unsigned device is a new device', () {
    final state = _eval([_device('A', signed: true), _device('B')]);
    expect(state?.deviceIds, ['B']);
    expect(state?.userId, '@kim:example.org');
  });

  test('blocked devices and devices we do not encrypt to are ignored', () {
    expect(
      _eval([_device('A', blocked: true), _device('B', encrypt: false)]),
      isNull,
    );
  });

  test('a verified device is not new', () {
    expect(_eval([_device('A', verified: true)]), isNull);
  });

  test('device ids are sorted and form the dismiss key', () {
    final state = _eval([_device('C'), _device('A')]);
    expect(state?.deviceIds, ['A', 'C']);
    expect(
      state?.dismissKey,
      '["@me:example.org","@kim:example.org",["A","C"]]',
    );
  });

  test('dismissed for this set of devices, back for a newer one', () {
    final first = _eval([_device('A')])!;
    expect(_eval([_device('A')], dismissed: {first.dismissKey}), isNull);
    expect(
      _eval([_device('A'), _device('B')], dismissed: {first.dismissKey}),
      isNotNull,
    );
  });

  test('ids that contain a comma do not collide with two ids (SEC L2)', () {
    final two = _eval([_device('A'), _device('B')])!;
    expect(_eval([_device('A,B')], dismissed: {two.dismissKey}), isNotNull);
  });

  test('a dismissal in one account does not hide the banner in another', () {
    final first = _eval([_device('A')])!;
    expect(
      _eval(
        [_device('A')],
        dismissed: {first.dismissKey},
        account: '@other:example.org',
      ),
      isNotNull,
    );
  });

  test('no devices, no banner', () {
    expect(_eval([]), isNull);
  });
}
