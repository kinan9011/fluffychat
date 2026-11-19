// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:odango/utils/matrix_room_id.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';

class ScheduledEncryptionUnavailable implements Exception {
  const ScheduledEncryptionUnavailable();

  @override
  String toString() => 'ScheduledEncryptionUnavailable';
}

class ScheduleDelayTooShort implements Exception {
  const ScheduleDelayTooShort();

  @override
  String toString() => 'ScheduleDelayTooShort';
}

/// A message the homeserver holds back (MSC4140), as the server lists it.
class ServerDelayedEvent {
  const ServerDelayedEvent({
    required this.delayId,
    required this.roomId,
    required this.type,
    required this.sendAt,
    required this.content,
  });

  final String delayId;
  final String roomId;
  final String type;
  final DateTime sendAt;
  final Map<String, Object?> content;
}

/// Delayed message events of the user's own homeserver. Everything the server
/// says is checked here; nothing about a delay (id, text) is logged.
class DelayedEventsApi {
  DelayedEventsApi(
    this.client, {
    bool Function()? encryptionReady,
    Future<Map<String, Object?>> Function(
      String roomId,
      Map<String, Object?> content,
    )?
    encrypt,
  }) : _encryptionReady =
           encryptionReady ??
           (() => client.encryption != null && client.encryptionEnabled),
       _encrypt =
           encrypt ??
           ((roomId, content) async => Map<String, Object?>.from(
             await client.encryption!.encryptGroupMessagePayload(
               roomId,
               content,
             ),
           ));

  static const maxPages = 5;
  static const maxEntries = 500;
  static const minDelay = Duration(minutes: 1);
  static const maxDelayMs = 400 * 24 * 60 * 60 * 1000;
  static const maxContentJsonUnits = 100000;
  static const _path = '/client/unstable/org.matrix.msc4140/delayed_events';
  static const _types = {EventTypes.Message, EventTypes.Encrypted};

  final Client client;
  final bool Function() _encryptionReady;
  final Future<Map<String, Object?>> Function(
    String roomId,
    Map<String, Object?> content,
  )
  _encrypt;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      Logs().w('[Scheduled] request failed (${e.runtimeType})');
      rethrow;
    }
  }

  /// Encrypts when the room is encrypted (now, with the room's current
  /// session: the server only ever holds ciphertext) and asks the server to
  /// send the event after [delay]. Returns the delay id.
  Future<String> scheduleMessage(
    Room room,
    Map<String, Object?> content,
    Duration delay,
  ) async {
    if (delay < minDelay) throw const ScheduleDelayTooShort();
    var payload = content;
    var type = EventTypes.Message;
    if (room.encrypted) {
      if (!_encryptionReady()) throw const ScheduledEncryptionUnavailable();
      payload = await _guard(() => _encrypt(room.id, content));
      if (!payload.containsKey('ciphertext')) {
        throw const ScheduledEncryptionUnavailable();
      }
      type = EventTypes.Encrypted;
    }
    final response = await _guard(
      () => client.request(
        RequestType.PUT,
        '/client/v3/rooms/${Uri.encodeComponent(room.id)}/send/'
        '${Uri.encodeComponent(type)}/'
        '${Uri.encodeComponent(client.generateUniqueTransactionId())}',
        data: payload,
        query: {'org.matrix.msc4140.delay': '${delay.inMilliseconds}'},
      ),
    );
    final id = response['delay_id'];
    if (!ScheduledEntry.isDelayId(id)) throw const FormatException('delay id');
    return id! as String;
  }

  /// Every delayed message event of the account. `complete` is false when a
  /// cap cut the list short: absence from it then proves nothing.
  Future<({List<ServerDelayedEvent> events, bool complete})> list() =>
      _guard(() async {
        final events = <ServerDelayedEvent>[];
        var spec = false;
        String? from;
        for (var page = 0; page < maxPages; page++) {
          Map<String, Object?> response;
          try {
            response = await _page(from, spec: spec);
          } on MatrixException catch (e) {
            final missing =
                e.response?.statusCode == 404 || e.errcode == 'M_UNRECOGNIZED';
            if (spec || page > 0 || !missing) rethrow;
            spec = true;
            response = await _page(from, spec: spec);
          }
          final items = response['delayed_events'] ?? response['scheduled'];
          if (items is List) {
            for (final item in items) {
              final event = parse(item);
              if (event == null) continue;
              if (events.length >= maxEntries) {
                return (events: events, complete: false);
              }
              events.add(event);
            }
          }
          final next = response['next_batch'];
          if (next is! String || next.isEmpty) {
            return (events: events, complete: true);
          }
          from = next;
        }
        return (events: events, complete: false);
      });

  Future<Map<String, Object?>> _page(String? from, {required bool spec}) =>
      client.request(
        RequestType.GET,
        spec ? '$_path/scheduled' : _path,
        query: {'from': ?from},
      );

  Future<void> sendNow(String delayId) => _manage(delayId, .send);

  Future<void> cancel(String delayId) => _manage(delayId, .cancel);

  Future<void> _manage(String delayId, DelayedEventAction action) async {
    if (!ScheduledEntry.isDelayId(delayId)) {
      throw const FormatException('delay id');
    }
    await _guard(() => client.manageDelayedEvent(delayId, action));
  }

  /// One entry of the server list, or null for anything that is not a plain
  /// delayed message event of ours (state events, other types, odd values).
  static ServerDelayedEvent? parse(Object? json) {
    if (json is! Map) return null;
    final id = json['delay_id'];
    final room = json['room_id'];
    final type = json['type'];
    final delay = json['delay'];
    final since = json['running_since'];
    final content = json['content'];
    if (!ScheduledEntry.isDelayId(id)) return null;
    if (room is! String || !isMatrixRoomId(room)) return null;
    if (!_types.contains(type) || json['state_key'] != null) return null;
    if (delay is! int || delay < 0 || delay > maxDelayMs) return null;
    if (since is! int || since < 0 || since > 4102444800000) return null;
    if (content is! Map || content.keys.any((k) => k is! String)) return null;
    try {
      if (jsonEncode(content).length > maxContentJsonUnits) return null;
    } catch (_) {
      return null;
    }
    return ServerDelayedEvent(
      delayId: id! as String,
      roomId: room,
      type: type! as String,
      sendAt: DateTime.fromMillisecondsSinceEpoch(since + delay),
      content: Map<String, Object?>.from(content),
    );
  }
}
