// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

const maxBackupDumpBytes = 256 * 1024 * 1024;

/// Boxes `MatrixSdkDatabase.importDump` dereferences unconditionally. Missing
/// one makes the import throw after the existing database was already cleared.
const requiredBackupBoxes = [
  'box_client',
  'box_account_data',
  'box_rooms',
  'box_to_device_queue',
  'box_preload_room_states',
  'box_non_preload_room_states',
  'box_room_members',
  'box_room_account_data',
  'box_inbound_group_session',
  'box_inbound_group_sessions_upload_queue',
  'box_outbound_group_session',
  'box_olm_session',
  'box_device_keys_list',
  'box_last_sent_olm_messages',
  'box_ssss_cache',
  'box_presences',
  'box_timeline_fragments',
  'box_seen_device_ids',
  'box_seen_device_keys',
];

class InvalidBackupException implements Exception {
  final bool tooLarge;

  const InvalidBackupException({this.tooLarge = false});

  @override
  String toString() => 'InvalidBackupException(tooLarge: $tooLarge)';
}

/// Returns the decoded dump if [bytes] is a backup that is safe to import.
/// Throws [InvalidBackupException] otherwise. Must run before the importer
/// clears the current database.
String validateBackupDump(
  Uint8List bytes, {
  int maxBytes = maxBackupDumpBytes,
}) {
  if (bytes.length > maxBytes) {
    throw const InvalidBackupException(tooLarge: true);
  }

  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const InvalidBackupException();
  }
  final decoded = _tryDecodeJson(text);
  if (decoded is! Map<String, Object?>) {
    throw const InvalidBackupException();
  }
  if (decoded.entries.any(
    (e) => !e.key.startsWith('box_') || e.value is! Map,
  )) {
    throw const InvalidBackupException();
  }
  if (requiredBackupBoxes.any((box) => !decoded.containsKey(box))) {
    throw const InvalidBackupException();
  }
  if ((decoded['box_client']! as Map).isEmpty) {
    throw const InvalidBackupException();
  }
  return text;
}

Object? _tryDecodeJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Validates [file] and only then calls [importDump], which clears the
/// current database before it reads anything.
Future<T> importBackupFile<T>(
  XFile file,
  Future<T> Function(String dump) importDump,
) async {
  if (await file.length() > maxBackupDumpBytes) {
    throw const InvalidBackupException(tooLarge: true);
  }
  final dump = await compute(validateBackupDump, await file.readAsBytes());
  return importDump(dump);
}
