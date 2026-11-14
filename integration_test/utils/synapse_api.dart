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
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://$homeserver/_matrix/client/v3$path'),
      );
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body ?? {}));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
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

  Future<void> sendText(String roomId, String text) => _request(
    'PUT',
    '/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/'
        '${DateTime.now().microsecondsSinceEpoch}',
    token: _token,
    body: {'msgtype': 'm.text', 'body': text},
  );

  Future<Object?> getAccountData(String type) => _request(
    'GET',
    '/user/${Uri.encodeComponent(userId)}/account_data/$type',
    token: _token,
  );

  Future<void> logout() => _request('POST', '/logout', token: _token);
}
