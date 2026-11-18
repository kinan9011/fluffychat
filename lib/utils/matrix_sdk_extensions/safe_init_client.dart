// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'flutter_matrix_dart_sdk_database/database_open_error.dart';

/// The SDK clears the database and the session secrets whenever `init()`
/// throws, also for a busy or full disk. That clear is held back here and
/// decided by [settleInitFailure].
class SafeInitClient extends Client {
  SafeInitClient(
    super.clientName, {
    required super.database,
    super.httpClient,
    super.verificationMethods,
    super.importantStateEvents,
    super.customImageResizer,
    super.logLevel,
    super.supportedLoginTypes,
    super.nativeImplementations,
    super.defaultNetworkRequestTimeout,
    super.enableDehydratedDevices,
    super.shareKeysWith,
    super.onSoftLogout,
    super.sendTimelineEventTimeout,
  });

  bool _initClearPending = false;

  @override
  Future<void> clear({
    SessionClearReason reason = SessionClearReason.unspecified,
  }) async {
    if (reason == SessionClearReason.initFailed) {
      _initClearPending = true;
      return;
    }
    await super.clear(reason: reason);
  }

  /// Throws [DatabaseOpenFailedException] and clears nothing when [error] says
  /// that the storage or the network was briefly unavailable. Otherwise the
  /// clear the SDK asked for runs, so restoring from the session backup works
  /// as before.
  Future<void> settleInitFailure(Object error) async {
    final pending = _initClearPending;
    _initClearPending = false;
    if (!pending) return;
    if (keepsDataAfterInitFailure(error)) {
      throw DatabaseOpenFailedException(clientName, error);
    }
    await super.clear(reason: SessionClearReason.initFailed);
  }
}
