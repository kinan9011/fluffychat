// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:math';

import 'package:matrix/matrix.dart';

const maxQuarantinedDatabases = 2;

const _sideFileSuffixes = ['-wal', '-shm', '-journal'];

Future<void> _renameFile(File file, String newPath) => file.rename(newPath);

RegExp _copyPattern(String fileName) =>
    RegExp('^${RegExp.escape(fileName)}\\.quarantine-(\\d+)\$');

Future<Map<int, String>> _copies(String path) async {
  final file = File(path);
  final pattern = _copyPattern(file.uri.pathSegments.last);
  final result = <int, String>{};
  await for (final entity in file.parent.list()) {
    final match = pattern.firstMatch(entity.uri.pathSegments.last);
    final sequence = int.tryParse(match?.group(1) ?? '');
    if (sequence == null || entity is! File) continue;
    result[sequence] = entity.path;
  }
  return result;
}

Future<void> _deleteWithSideFiles(String path) async {
  for (final suffix in ['', ..._sideFileSuffixes]) {
    try {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    } catch (e, s) {
      Logs().w('Unable to delete a database file', e, s);
    }
  }
}

/// A database that is proven to be damaged is moved aside instead of deleted,
/// so that the data is still on the device. Copies are numbered with a
/// sequence (highest existing + 1), never by time, so a clock that jumps
/// cannot make the newest copy look old. Throws if the database cannot be
/// moved: nothing is deleted then and the caller fails closed.
Future<void> quarantineDatabase(
  String path, {
  Future<void> Function(File file, String newPath) rename = _renameFile,
}) async {
  final database = File(path);
  if (!await database.exists()) return;
  final existing = await _copies(path);
  final sequence = existing.keys.fold<int>(0, max) + 1;
  final target = '$path.quarantine-$sequence';
  await rename(database, target);
  for (final suffix in _sideFileSuffixes) {
    final sideFile = File('$path$suffix');
    try {
      if (await sideFile.exists()) await rename(sideFile, '$target$suffix');
    } catch (e, s) {
      Logs().w('Unable to quarantine a database side file, deleting it', e, s);
      await _deleteWithSideFiles(path);
    }
  }
  try {
    final copies = await _copies(path);
    final newestFirst = copies.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final old in newestFirst.skip(maxQuarantinedDatabases)) {
      await _deleteWithSideFiles(copies[old]!);
    }
  } catch (e, s) {
    Logs().w('Unable to remove old quarantined databases', e, s);
  }
}

/// Part of the confirmed reset: quarantined copies hold the user's data too.
Future<void> deleteQuarantinedDatabases(String path) async {
  for (final copy in (await _copies(path)).values) {
    await _deleteWithSideFiles(copy);
  }
}
