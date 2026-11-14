// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

enum DatabaseFileState { none, plaintext, encrypted }

final _plaintextHeader = [...'SQLite format 3'.codeUnits, 0];

/// A plaintext SQLite file starts with a fixed 16 byte header, an SQLCipher
/// file does not. Anything unclear counts as encrypted, so that an unknown
/// file is never replaced without the user's consent.
Future<DatabaseFileState> databaseFileState(File file) async {
  try {
    if (!await file.exists()) return DatabaseFileState.none;
    final handle = await file.open();
    try {
      final head = await handle.read(_plaintextHeader.length);
      if (head.isEmpty) return DatabaseFileState.none;
      final isPlaintext =
          head.length == _plaintextHeader.length &&
          List.generate(
            head.length,
            (i) => head[i] == _plaintextHeader[i],
          ).every((same) => same);
      return isPlaintext
          ? DatabaseFileState.plaintext
          : DatabaseFileState.encrypted;
    } finally {
      await handle.close();
    }
  } catch (_) {
    return DatabaseFileState.encrypted;
  }
}
