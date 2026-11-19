// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat/display_text.dart';

enum DeviceTrust { verified, unverified, blocked, unknown }

/// Blocked beats verified beats unverified. A device whose keys we do not have
/// is `unknown` and is never shown as verified.
DeviceTrust deviceTrust({
  required bool hasKeys,
  bool blocked = false,
  bool verified = false,
}) {
  if (!hasKeys) return DeviceTrust.unknown;
  if (blocked) return DeviceTrust.blocked;
  return verified ? DeviceTrust.verified : DeviceTrust.unverified;
}

class DeviceRow {
  const DeviceRow({
    required this.deviceId,
    required this.name,
    required this.trust,
    required this.lastSeen,
    required this.isThisDevice,
  });

  final String deviceId;
  final String name;
  final DeviceTrust trust;
  final DateTime? lastSeen;
  final bool isThisDevice;
}

final _earliest = DateTime.utc(2000).millisecondsSinceEpoch;
final _latest = DateTime.utc(2100).millisecondsSinceEpoch;

/// Server supplied timestamps outside 2000..2100 are nonsense: no date.
DateTime? sanitizedLastSeen(int? ts) {
  if (ts == null || ts < _earliest || ts > _latest) return null;
  return DateTime.fromMillisecondsSinceEpoch(ts);
}

/// This device first, then the others by last activity, newest first and
/// unknown activity last. Names are other software's strings: cleaned and cut.
List<DeviceRow> buildDeviceRows(
  List<Device> devices,
  String? ownDeviceId, {
  required Map<String, DeviceTrust> trust,
  String unnamed = 'Unknown device',
}) {
  final rows = <DeviceRow>[];
  final seen = <String>{};
  for (final device in devices) {
    if (!seen.add(device.deviceId)) continue;
    final name = safeDisplayText(device.displayName ?? '', maxGraphemes: 64);
    rows.add(
      DeviceRow(
        deviceId: device.deviceId,
        name: name.isEmpty ? unnamed : name,
        trust: trust[device.deviceId] ?? DeviceTrust.unknown,
        lastSeen: sanitizedLastSeen(device.lastSeenTs),
        isThisDevice: ownDeviceId != null && device.deviceId == ownDeviceId,
      ),
    );
  }
  rows.sort((a, b) {
    if (a.isThisDevice != b.isThisDevice) return a.isThisDevice ? -1 : 1;
    final x = a.lastSeen;
    final y = b.lastSeen;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return rows;
}

/// The ids "Sign out all other sessions" may delete. Never contains the id of
/// this device; empty when this device's id is unknown, because then no id can
/// be told apart from it.
List<String> otherDeviceIds(List<Device> devices, String? ownDeviceId) {
  if (ownDeviceId == null) return const [];
  return {
    for (final device in devices)
      if (device.deviceId != ownDeviceId) device.deviceId,
  }.toList();
}
