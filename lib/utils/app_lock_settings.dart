// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

typedef AppLockRead = ({String? pincode, bool useBiometrics, bool failed});

Future<AppLockRead> readAppLockSettings(FlutterSecureStorage storage) async {
  try {
    final pincode = await storage.read(key: 'chat.fluffy.app_lock');
    final biometrics = await storage.read(key: 'chat.fluffy.use_biometrics');
    return (
      pincode: pincode,
      useBiometrics: biometrics == 'true',
      failed: false,
    );
  } catch (e) {
    Logs().w('Unable to read the app lock settings', e);
    return (pincode: null, useBiometrics: false, failed: true);
  }
}

/// A PIN that cannot be read must not open the app: there is no way to know
/// whether one is set. Without a signed-in account there is nothing to protect.
bool appLockMustBlock(AppLockRead read, {required bool signedIn}) =>
    read.failed && signedIn;
