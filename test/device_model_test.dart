// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/devices/device_model.dart';

Device _device(String id, {String? name, int? ts}) =>
    Device(deviceId: id, displayName: name, lastSeenTs: ts);

void main() {
  final now = DateTime(2030, 5, 10).millisecondsSinceEpoch;

  group('otherDeviceIds', () {
    test('never contains this device', () {
      final ids = otherDeviceIds([
        _device('OWN'),
        _device('A'),
        _device('B'),
      ], 'OWN');
      expect(ids, ['A', 'B']);
      expect(ids, isNot(contains('OWN')));
    });

    test('is empty when the own id is unknown', () {
      expect(otherDeviceIds([_device('A'), _device('B')], null), isEmpty);
    });

    test('is empty when this is the only device', () {
      expect(otherDeviceIds([_device('OWN')], 'OWN'), isEmpty);
    });

    test('a duplicated id is listed once', () {
      expect(
        otherDeviceIds([_device('A'), _device('A'), _device('OWN')], 'OWN'),
        ['A'],
      );
    });
  });

  group('deviceTrust', () {
    test('without keys it is unknown, never verified', () {
      expect(deviceTrust(hasKeys: false, verified: true), DeviceTrust.unknown);
    });

    test('blocked beats verified beats unverified', () {
      expect(
        deviceTrust(hasKeys: true, blocked: true, verified: true),
        DeviceTrust.blocked,
      );
      expect(deviceTrust(hasKeys: true, verified: true), DeviceTrust.verified);
      expect(deviceTrust(hasKeys: true), DeviceTrust.unverified);
    });
  });

  group('buildDeviceRows', () {
    test('this device first, then newest activity, unknown activity last', () {
      final rows = buildDeviceRows(
        [
          _device('OLD', name: 'Old', ts: now - 5000),
          _device('NEW', name: 'New', ts: now - 1000),
          _device('NONE', name: 'None'),
          _device('OWN', name: 'Mine', ts: now - 9000),
        ],
        'OWN',
        trust: const {},
      );
      expect(rows.map((r) => r.deviceId), ['OWN', 'NEW', 'OLD', 'NONE']);
      expect(rows.first.isThisDevice, isTrue);
      expect(rows.skip(1).any((r) => r.isThisDevice), isFalse);
    });

    test('a hostile name is cleaned and cut', () {
      final rows = buildDeviceRows(
        [
          _device('A', name: 'Evil\u202E\u0000 name\n${'x' * 500}'),
          _device('B', name: '   '),
          _device('C'),
        ],
        'OWN',
        trust: const {},
        unnamed: 'Unnamed',
      );
      final a = rows.firstWhere((r) => r.deviceId == 'A');
      expect(a.name.characters.length, lessThanOrEqualTo(64));
      expect(a.name, isNot(contains('\u202E')));
      expect(a.name, isNot(contains('\u0000')));
      expect(a.name, isNot(contains('\n')));
      expect(rows.firstWhere((r) => r.deviceId == 'B').name, 'Unnamed');
      expect(rows.firstWhere((r) => r.deviceId == 'C').name, 'Unnamed');
    });

    test('timestamps outside 2000..2100 become no date', () {
      expect(sanitizedLastSeen(-1), isNull);
      expect(sanitizedLastSeen(0), isNull);
      expect(sanitizedLastSeen(1 << 60), isNull);
      expect(sanitizedLastSeen(null), isNull);
      expect(sanitizedLastSeen(now), isNotNull);
    });

    test('the trust map is applied, unknown by default', () {
      final rows = buildDeviceRows(
        [_device('A'), _device('B')],
        'OWN',
        trust: {'A': DeviceTrust.verified},
      );
      expect(
        rows.firstWhere((r) => r.deviceId == 'A').trust,
        DeviceTrust.verified,
      );
      expect(
        rows.firstWhere((r) => r.deviceId == 'B').trust,
        DeviceTrust.unknown,
      );
    });

    test('duplicate ids produce one row', () {
      final rows = buildDeviceRows(
        [_device('A'), _device('A')],
        'OWN',
        trust: const {},
      );
      expect(rows, hasLength(1));
    });
  });
}
