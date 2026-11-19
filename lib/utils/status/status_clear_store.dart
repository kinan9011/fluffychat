// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/privacy/presence_policy.dart';
import 'package:odango/utils/status/status_policy.dart';

class StatusClearRecord {
  const StatusClearRecord(this.userId, this.message, this.clearAtMs);

  final String userId;
  final String message;
  final int clearAtMs;

  @override
  bool operator ==(Object other) =>
      other is StatusClearRecord &&
      other.userId == userId &&
      other.message == message &&
      other.clearAtMs == clearAtMs;

  @override
  int get hashCode => Object.hash(userId, message, clearAtMs);
}

/// "Clear after" of a status is client managed: the server keeps presence
/// text until someone replaces it. Remembers, per account, which text should
/// go at which time, and removes it only if the server still shows that text.
class StatusClearStore {
  StatusClearStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const key = 'com.swovo.odango.status_clear';
  static const maxRecords = 16;
  static const maxUserIdLength = 256;

  final DateTime Function() _now;

  List<StatusClearRecord> read() {
    final String? raw;
    try {
      raw = AppSettings.store.getString(key);
    } catch (_) {
      return const [];
    }
    if (raw == null) return const [];
    final now = _now().millisecondsSinceEpoch;
    const year = 365 * 24 * 3600 * 1000;
    final records = <String, StatusClearRecord>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      for (final entry in decoded.take(maxRecords)) {
        if (entry is! Map) continue;
        final userId = entry['user_id'];
        final message = entry['message'];
        final at = entry['clear_at'];
        if (userId is! String ||
            userId.isEmpty ||
            userId.length > maxUserIdLength ||
            message is! String ||
            message.isEmpty ||
            message.length > maxStatusLength * 4 ||
            at is! int ||
            at < now - year ||
            at > now + 2 * year) {
          continue;
        }
        records[userId] = StatusClearRecord(userId, message, at);
      }
    } catch (_) {
      return const [];
    }
    return records.values.toList();
  }

  StatusClearRecord? recordFor(String userId) {
    for (final record in read()) {
      if (record.userId == userId) return record;
    }
    return null;
  }

  Future<void> _write(List<StatusClearRecord> records) {
    final limited = records.length > maxRecords
        ? records.sublist(records.length - maxRecords)
        : records;
    return AppSettings.store.setString(
      key,
      jsonEncode([
        for (final r in limited)
          {'user_id': r.userId, 'message': r.message, 'clear_at': r.clearAtMs},
      ]),
    );
  }

  Future<void> arm(String userId, String message, DateTime clearAt) async {
    final others = read().where((r) => r.userId != userId).toList();
    await _write([
      ...others,
      StatusClearRecord(userId, message, clearAt.millisecondsSinceEpoch),
    ]);
  }

  Future<void> disarm(String userId) async {
    final others = read().where((r) => r.userId != userId).toList();
    await _write(others);
  }

  /// Removes the status of [client] if its deadline has passed and the server
  /// still shows the text that was armed (asked from the server: the SDK's
  /// own presence cache is not refreshed for the user's own status). A newer
  /// status set elsewhere is never touched. Failures keep the record for the
  /// next try.
  ///
  /// Nothing is sent before the first sync, and the presence that goes with the
  /// cleared status is the one the sync itself would announce
  /// ([PresencePolicy.syncPresence]): offline for a hidden user, never online
  /// while the app is not in the foreground.
  Future<void> clearIfDue(Client client, {bool foreground = true}) async {
    final userId = client.userID;
    if (userId == null || !client.isLogged()) return;
    final record = recordFor(userId);
    if (record == null) return;
    if (_now().millisecondsSinceEpoch < record.clearAtMs) return;
    try {
      await client.firstSyncReceived;
      if (recordFor(userId) != record) return;
      final current = await client.getPresence(userId);
      if (recordFor(userId) != record) return;
      if (current.statusMsg == record.message) {
        await client.setPresence(
          userId,
          PresencePolicy.fromSettings().syncPresence(foreground: foreground) ??
              PresenceType.online,
          statusMsg: '',
        );
      }
      if (recordFor(userId) == record) await disarm(userId);
    } on MatrixException catch (e) {
      if (e.error == MatrixError.M_NOT_FOUND && recordFor(userId) == record) {
        await disarm(userId);
      }
    } catch (e) {
      Logs().w('[Status] could not clear the status (${e.runtimeType})');
    }
  }
}
