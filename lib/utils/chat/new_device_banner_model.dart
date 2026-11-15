// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// What the user dismissed in this app session. Device ids only, in memory.
abstract class NewDeviceDismissals {
  static final Set<String> _keys = {};

  static Set<String> get keys => Set.unmodifiable(_keys);

  static void dismiss(NewDeviceBannerState state) =>
      _keys.add(state.dismissKey);

  @visibleForTesting
  static void reset() => _keys.clear();
}

class DeviceInfo {
  final String id;
  final bool verified;
  final bool blocked;
  final bool signed;
  final bool encryptToDevice;

  const DeviceInfo({
    required this.id,
    required this.verified,
    required this.blocked,
    required this.signed,
    required this.encryptToDevice,
  });
}

class NewDeviceBannerState {
  final String accountId;
  final String userId;
  final List<String> deviceIds;

  const NewDeviceBannerState({
    required this.accountId,
    required this.userId,
    required this.deviceIds,
  });

  /// The banner is dismissed for exactly this account, partner and set of
  /// devices: one more new device brings it back. Device ids are opaque, so
  /// the key is encoded, not joined.
  String get dismissKey => jsonEncode([accountId, userId, deviceIds]);
}

/// A partner you verified has a device that nobody vouches for: not verified,
/// not blocked, not signed by their own keys. Reads trust state, never
/// changes it. An unverified partner shows nothing here: every device of
/// theirs would be "new".
NewDeviceBannerState? evaluateNewDevices({
  required String accountId,
  required String partnerId,
  required bool partnerVerified,
  required Iterable<DeviceInfo> devices,
  required Set<String> dismissed,
}) {
  if (!partnerVerified) return null;
  final ids = devices
      .where(
        (device) =>
            !device.verified &&
            !device.blocked &&
            !device.signed &&
            device.encryptToDevice,
      )
      .map((device) => device.id)
      .sorted((a, b) => a.compareTo(b));
  if (ids.isEmpty) return null;
  final state = NewDeviceBannerState(
    accountId: accountId,
    userId: partnerId,
    deviceIds: ids,
  );
  return dismissed.contains(state.dismissKey) ? null : state;
}

NewDeviceBannerState? newDeviceBanner(
  Room room, {
  required Set<String> dismissed,
}) {
  if (!room.encrypted || !room.isDirectChat) return null;
  final partner = room.directChatMatrixID;
  if (partner == null) return null;
  final keys = room.client.userDeviceKeys[partner];
  if (keys == null) return null;
  return evaluateNewDevices(
    accountId: room.client.userID ?? '',
    partnerId: partner,
    partnerVerified: keys.masterKey?.verified == true,
    devices: [
      for (final device in keys.deviceKeys.values)
        if (device.deviceId != null)
          DeviceInfo(
            id: device.deviceId!,
            verified: device.verified,
            blocked: device.blocked,
            signed: device.signed,
            encryptToDevice: device.encryptToDevice,
          ),
    ],
    dismissed: dismissed,
  );
}

@visibleForTesting
NewDeviceBannerState? Function(Room room, {required Set<String> dismissed})
loadNewDeviceBanner = newDeviceBanner;

NewDeviceBannerState? lookUpNewDeviceBanner(
  Room room, {
  required Set<String> dismissed,
}) => loadNewDeviceBanner(room, dismissed: dismissed);
