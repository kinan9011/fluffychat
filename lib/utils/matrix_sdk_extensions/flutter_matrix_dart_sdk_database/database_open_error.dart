// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum DatabaseOpenFailure { corrupt, other }

/// The database could not be opened for a reason that does not prove that the
/// file is damaged (full disk, lock contention, I/O error, wrong key...). The
/// file is left as it is and the user decides.
class DatabaseOpenFailedException implements Exception {
  final String clientName;
  final Object error;

  const DatabaseOpenFailedException(this.clientName, this.error);

  /// Moving the account's data aside only helps when the file itself is
  /// unusable (damaged, or not a database for this key). A busy, full or
  /// unreadable disk, the network or the key store say nothing about the
  /// file, so there Retry is the answer.
  bool get setAsideMayHelp {
    final cause = _originalException(error);
    if (cause is! DatabaseException) return false;
    final code = cause.getResultCode();
    if (code == null || code < 0) return false;
    return const {_sqliteCorrupt, _sqliteNotADatabase}.contains(code & 0xFF);
  }

  @override
  String toString() => 'DatabaseOpenFailedException';
}

const _sqliteCorrupt = 11;
const _sqliteNotADatabase = 26;

/// Deny by default: only SQLITE_CORRUPT (the primary code, extended codes map
/// by the low byte) counts as a damaged file. SQLITE_NOTADB looks the same for
/// a damaged file and a wrong key, so it never does.
DatabaseOpenFailure classifyDatabaseOpenError(Object error) {
  if (error is! DatabaseException) return DatabaseOpenFailure.other;
  final code = error.getResultCode();
  if (code == null || code < 0) return DatabaseOpenFailure.other;
  return code & 0xFF == _sqliteCorrupt
      ? DatabaseOpenFailure.corrupt
      : DatabaseOpenFailure.other;
}

/// Deny by default for storage: a SQLite, file-system, secure-storage or
/// network error keeps the data. Only failures that come from the session itself (olm pickle,
/// server answer, format) let the SDK clear as before.
bool keepsDataAfterInitFailure(Object error) {
  final cause = _originalException(error);
  return cause is DatabaseException ||
      cause is IOException ||
      cause is TimeoutException ||
      cause is PlatformException ||
      cause is http.ClientException;
}

/// Workaround: the SDK wraps the failure of `init()` in a ClientInitException
/// but does not export the class, and the app does not import SDK internals.
Object _originalException(Object error) {
  try {
    // ignore: avoid-dynamic
    final cause = (error as dynamic).originalException;
    return cause is Object ? cause : error;
  } catch (_) {
    return error;
  }
}
