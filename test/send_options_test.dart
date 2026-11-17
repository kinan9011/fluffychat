// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/pages/chat/scheduling/send_options_flow.dart';
import 'package:fluffychat/utils/scheduling/send_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

class _HangingPresence extends http.BaseClient {
  final inner = FakeMatrixApi();
  var presenceRequests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!request.url.path.contains('/presence/')) return inner.send(request);
    presenceRequests++;
    return Completer<http.StreamedResponse>().future;
  }
}

List<SendOption> options({
  String text = 'hello',
  bool editing = false,
  bool canSend = true,
  bool offline = false,
}) => availableSendOptions(
  text: text,
  editing: editing,
  canSend: canSend,
  partnerPresenceKnownOffline: offline,
);

void main() {
  test('a message offers silent and schedule', () {
    expect(options(), [SendOption.silent, SendOption.schedule]);
  });

  test('when online needs a partner known to be offline', () {
    expect(options(offline: true), [
      SendOption.silent,
      SendOption.schedule,
      SendOption.whenOnline,
    ]);
  });

  test('nothing for an empty or blank message', () {
    expect(options(text: ''), isEmpty);
    expect(options(text: '  \n '), isEmpty);
  });

  test('nothing while editing', () {
    expect(options(editing: true), isEmpty);
  });

  test('nothing for commands, also with a leading slash and a word', () {
    expect(options(text: '/me waves'), isEmpty);
    expect(options(text: '/shrug'), isEmpty);
  });

  test('a slash that is not a command is a message', () {
    expect(options(text: '/ not a command'), isNotEmpty);
    expect(options(text: 'a /me b'), isNotEmpty);
  });

  test('nothing in a room the user cannot write in', () {
    expect(options(canSend: false), isEmpty);
    expect(options(canSend: false, offline: true), isEmpty);
  });

  group('presenceKnownOffline', () {
    final active = DateTime(2025, 11, 13, 14);

    test('offline with a last activity is known', () {
      expect(presenceKnownOffline(online: false, lastActive: active), isTrue);
    });

    test('online is not offline', () {
      expect(presenceKnownOffline(online: true, lastActive: active), isFalse);
    });

    test('offline without a last activity is a server hiding presence', () {
      expect(presenceKnownOffline(online: false), isFalse);
    });
  });

  group('the partner whose presence is known offline', () {
    const partner = '@mara:example.org';

    Future<(Room, _HangingPresence)> directRoom() async {
      final server = _HangingPresence();
      final client = await prepareTestClient(
        clientName: 'options-presence',
        httpClient: server,
      );
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          partner: ['!dm:example.org'],
        },
      );
      return (Room(id: '!dm:example.org', client: client), server);
    }

    test('an unknown presence answers at once and asks no server', () async {
      final (room, server) = await directRoom();
      expect(
        await offlinePartnerOf(room).timeout(const Duration(milliseconds: 500)),
        isNull,
      );
      expect(server.presenceRequests, 0);
    });

    test('a cached offline presence with a last activity counts', () async {
      final (room, _) = await directRoom();
      await room.client.database.storePresence(
        partner,
        CachedPresence.fromJson({
          'user_id': partner,
          'presence': 'offline',
          'last_active_timestamp': 1700000000000,
        }),
      );
      expect(await offlinePartnerOf(room), partner);
    });

    test('a cached online presence does not', () async {
      final (room, _) = await directRoom();
      await room.client.database.storePresence(
        partner,
        CachedPresence.fromJson({'user_id': partner, 'presence': 'online'}),
      );
      expect(await offlinePartnerOf(room), isNull);
    });
  });
}
