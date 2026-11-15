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

  SynapseUser._(this.userId, this._token);

  static Future<Object?> _request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
    bool allow404 = false,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://$homeserver/_matrix/client/v3$path'),
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

  Future<void> logout() => _request('POST', '/logout', token: _token);
}
