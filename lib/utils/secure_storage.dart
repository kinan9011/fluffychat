// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The Android plugin deletes an entry and returns null when it fails to
/// decrypt it (resetOnError, on by default). For the database key that would
/// silently turn a transient keystore error into the loss of all local data,
/// and for the app lock PIN into a disabled lock. Errors must surface instead.
FlutterSecureStorage createSecureStorage({
  IOSOptions iOptions = IOSOptions.defaultOptions,
}) => FlutterSecureStorage(
  iOptions: iOptions,
  aOptions: const AndroidOptions(resetOnError: false),
);
