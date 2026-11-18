// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/glass_policy.dart';

/// Whatever machine runs the tests, the glass looks the same: the device is
/// not low end unless a test says so.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  DeviceClass.lowEnd = false;
  await testMain();
}
