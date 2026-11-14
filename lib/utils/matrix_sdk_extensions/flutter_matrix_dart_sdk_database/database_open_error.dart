// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum DatabaseOpenFailure { corrupt, other }

/// The database could not be opened for a reason that does not prove that the
/// file is damaged (full disk, lock contention, I/O error, wrong key...). The
/// file is left as it is and the user decides.
class DatabaseOpenFailedException implements Exception {
  final String clientName;
  final Object error;

  const DatabaseOpenFailedException(this.clientName, this.error);

  @override
  String toString() => 'DatabaseOpenFailedException';
}

const _sqliteCorrupt = 11;

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
