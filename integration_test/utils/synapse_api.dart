// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import '../data/environment_constants.dart';

/// Minimal client for the integration Synapse, so a second user can act
/// without a second app instance.
class SynapseUser {
  final String userId;
  final String _token;
  final String _deviceId;

  SynapseUser._(this.userId, this._token, this._deviceId);

  static Future<Object?> _request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
    bool allow404 = false,
    String prefix = '/_matrix/client/v3',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://$homeserver$prefix$path'),
      );
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      if (method != 'GET') request.write(jsonEncode(body ?? {}));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (allow404 && response.statusCode == 404) return null;
      if (response.statusCode >= 300) {
        throw Exception('$method $path failed: ${response.statusCode}');
      }
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  static Future<SynapseUser> login(String user, String password) async {
    final json =
        await _request(
              'POST',
              '/login',
              body: {
                'type': 'm.login.password',
                'identifier': {'type': 'm.id.user', 'user': user},
                'password': password,
              },
            )
            as Map<String, Object?>;
    return SynapseUser._(
      json['user_id']! as String,
      json['access_token']! as String,
      json['device_id']! as String,
    );
  }

  Future<String> createRoom(
    String name, {
    List<String> invite = const [],
  }) async {
    final json =
        await _request(
              'POST',
              '/createRoom',
              token: _token,
              body: {'name': name, 'preset': 'private_chat', 'invite': invite},
            )
            as Map<String, Object?>;
    return json['room_id']! as String;
  }

  Future<void> join(String roomId) =>
      _request('POST', '/join/${Uri.encodeComponent(roomId)}', token: _token);

  Future<String> sendText(String roomId, String text) =>
      _send(roomId, {'msgtype': 'm.text', 'body': text});

  /// Synapse rate limits messages per user: back off and retry on a 429.
  Future<String> _send(String roomId, Map<String, Object?> body) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final json =
            await _request(
                  'PUT',
                  '/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/'
                      '${DateTime.now().microsecondsSinceEpoch}',
                  token: _token,
                  body: body,
                )
                as Map<String, Object?>;
        return json['event_id']! as String;
      } on Exception catch (e) {
        if (attempt >= 8 || !e.toString().contains('429')) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// A message that mentions [mentionedUserId] the intentional way
  /// (`m.mentions`), which is what raises the highlight count.
  Future<String> sendMention(
    String roomId,
    String text,
    String mentionedUserId,
  ) => _send(roomId, {
    'msgtype': 'm.text',
    'body': text,
    'm.mentions': {
      'user_ids': [mentionedUserId],
    },
  });

  /// Content of the newest `m.room.message` of [senderId] as the homeserver
  /// stores it.
  Future<Map<String, Object?>> latestMessageFrom(
    String roomId,
    String senderId,
  ) async {
    final json =
        await _request(
              'GET',
              '/rooms/${Uri.encodeComponent(roomId)}/messages?dir=b&limit=30',
              token: _token,
            )
            as Map<String, Object?>;
    for (final event in json['chunk']! as List) {
      if (event is Map &&
          event['type'] == 'm.room.message' &&
          event['sender'] == senderId) {
        return Map<String, Object?>.from(event['content'] as Map);
      }
    }
    throw StateError('The homeserver has no message of that sender');
  }

  /// How many messages the homeserver holds back for this user (MSC4140).
  Future<int> delayedEventCount() async {
    for (var attempt = 0; ; attempt++) {
      try {
        final json =
            await _request(
                  'GET',
                  '/delayed_events',
                  token: _token,
                  prefix: '/_matrix/client/unstable/org.matrix.msc4140',
                )
                as Map<String, Object?>;
        return ((json['delayed_events'] ?? json['scheduled']) as List).length;
      } on Exception catch (e) {
        if (attempt >= 8 || !e.toString().contains('429')) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// The presence the homeserver reports for this user.
  Future<String> presence() async {
    final json =
        await _request(
              'GET',
              '/presence/${Uri.encodeComponent(userId)}/status',
              token: _token,
            )
            as Map<String, Object?>;
    return json['presence']! as String;
  }

  /// Content of a state event of the room, or null when there is none.
  Future<Map<String, Object?>?> stateContent(String roomId, String type) async {
    final json = await _request(
      'GET',
      '/rooms/${Uri.encodeComponent(roomId)}/state/$type/',
      token: _token,
      allow404: true,
    );
    return json == null ? null : Map<String, Object?>.from(json as Map);
  }

  /// Content of the newest event of [type] (optionally of [senderId]) as the
  /// homeserver stores it, or null.
  Future<Map<String, Object?>?> latestEvent(
    String roomId,
    String type, {
    String? senderId,
  }) async {
    final json =
        await _request(
              'GET',
              '/rooms/${Uri.encodeComponent(roomId)}/messages?dir=b&limit=50',
              token: _token,
            )
            as Map<String, Object?>;
    for (final event in json['chunk']! as List) {
      if (event is Map &&
          event['type'] == type &&
          (senderId == null || event['sender'] == senderId)) {
        return Map<String, Object?>.from(event['content'] as Map);
      }
    }
    return null;
  }

  /// The ids of the thread roots of the room (replies from anyone).
  Future<List<String>> threadRootIds(String roomId) async {
    final json =
        await _request(
              'GET',
              '/rooms/${Uri.encodeComponent(roomId)}/threads',
              token: _token,
              prefix: '/_matrix/client/v1',
            )
            as Map<String, Object?>;
    return [
      for (final event in json['chunk']! as List)
        (event as Map)['event_id']! as String,
    ];
  }

  Future<void> sendMany(String roomId, int count, String prefix) async {
    for (var i = 1; i <= count; i++) {
      await sendText(roomId, '$prefix $i');
    }
  }

  Future<Object?> getRoomAccountData(String roomId, String type) => _request(
    'GET',
    '/user/${Uri.encodeComponent(userId)}/rooms/${Uri.encodeComponent(roomId)}'
        '/account_data/$type',
    token: _token,
    allow404: true,
  );

  /// Users with a read receipt (public or own private) on [eventId], as the
  /// homeserver reports them to this user in a fresh initial sync.
  Future<Set<String>> receiptUsers(String roomId, String eventId) async {
    // Synapse caches identical sync requests for a while: vary the filter.
    final limit = 1 + DateTime.now().microsecondsSinceEpoch % 9973;
    final filter = jsonEncode({
      'room': {
        'timeline': {'limit': limit},
      },
    });
    final json =
        await _request(
              'GET',
              '/sync?timeout=0&filter=${Uri.encodeComponent(filter)}',
              token: _token,
            )
            as Map<String, Object?>;
    final rooms = (json['rooms'] as Map?)?['join'] as Map?;
    final events = (rooms?[roomId] as Map?)?['ephemeral'] as Map?;
    final users = <String>{};
    for (final event in (events?['events'] as List? ?? const [])) {
      if (event is! Map || event['type'] != 'm.receipt') continue;
      final byType = (event['content'] as Map?)?[eventId] as Map?;
      for (final receipt in (byType ?? const {}).values) {
        users.addAll(((receipt as Map).keys).cast<String>());
      }
    }
    return users;
  }

  Future<Object?> getAccountData(String type) => _request(
    'GET',
    '/user/${Uri.encodeComponent(userId)}/account_data/$type',
    token: _token,
  );

  /// Ids of every device (session) of this user.
  Future<List<String>> deviceIds() async {
    final json =
        await _request('GET', '/devices', token: _token)
            as Map<String, Object?>;
    return [
      for (final device in (json['devices'] as List? ?? const []))
        (device as Map)['device_id']! as String,
    ];
  }

  Future<String?> deviceName(String deviceId) async {
    final json =
        await _request(
              'GET',
              '/devices/${Uri.encodeComponent(deviceId)}',
              token: _token,
              allow404: true,
            )
            as Map<String, Object?>?;
    return json?['display_name'] as String?;
  }

  Future<void> logout() => _request('POST', '/logout', token: _token);

  /// Gives this session device keys, so the app treats the user as someone
  /// who can receive encrypted messages (the app decides on that by asking
  /// the homeserver for the keys of the other user). The keys are made up:
  /// nobody can decrypt anything with them.
  Future<void> uploadDeviceKeys() async {
    final id = _deviceId;
    final key = base64Encode(List.filled(32, 7)).replaceAll('=', '');
    final signature = base64Encode(List.filled(64, 9)).replaceAll('=', '');
    await _request(
      'POST',
      '/keys/upload',
      token: _token,
      body: {
        'device_keys': {
          'user_id': userId,
          'device_id': id,
          'algorithms': [
            'm.olm.v1.curve25519-aes-sha2',
            'm.megolm.v1.aes-sha2',
          ],
          'keys': {'curve25519:$id': key, 'ed25519:$id': key},
          'signatures': {
            userId: {'ed25519:$id': signature},
          },
        },
      },
    );
  }

  /// The state events (`type` -> content) of the room this user shares with
  /// [otherUserId] as a direct chat (an invite or join of the other user and
  /// `is_direct`), or null when there is none.
  Future<Map<String, Map<String, Object?>>?> directRoomWith(
    String otherUserId,
  ) async {
    final rooms =
        await _request('GET', '/joined_rooms', token: _token)
            as Map<String, Object?>;
    for (final roomId in (rooms['joined_rooms'] as List? ?? const [])) {
      final events =
          await _request(
                'GET',
                '/rooms/${Uri.encodeComponent(roomId as String)}/state',
                token: _token,
              )
              as List;
      final byType = <String, Map<String, Object?>>{};
      var isDirectInvite = false;
      for (final event in events.cast<Map>()) {
        final type = event['type']! as String;
        final content = Map<String, Object?>.from(event['content'] as Map);
        byType[type] = content;
        if (type == 'm.room.member' &&
            event['state_key'] == otherUserId &&
            content['is_direct'] == true) {
          isDirectInvite = true;
        }
      }
      if (isDirectInvite) return byType;
    }
    return null;
  }
}
