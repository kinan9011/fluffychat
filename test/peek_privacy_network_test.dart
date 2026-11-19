// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/chat_list/peek_controller.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

void main() {
  late RecordingApi api;
  late Client client;

  setUp(() async {
    api = RecordingApi();
    client = await prepareTestClient(httpClient: api);
    client.backgroundSync = false;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() => client.dispose(closeDatabase: true));

  for (final public in [false, true]) {
    test('peeking sends no receipt, marker, typing or presence '
        '(public receipts ${public ? 'on' : 'off'})', () async {
      await AppSettings.sendPublicReadReceipts.setItem(public);
      await AppSettings.sendTypingNotifications.setItem(public);
      final room = client.rooms.firstWhere(
        (r) => r.membership == Membership.join,
      );
      api.clear();
      final controller = PeekController(room);
      await controller.open();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(controller.events.value, isNotEmpty);
      controller.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      for (final path in [
        '/receipt/',
        '/read_markers',
        '/typing/',
        '/presence/',
        '/send/',
        '/redact/',
      ]) {
        expect(api.requests(path), isEmpty, reason: path);
      }
      expect(
        api.log.where((r) => r.method != 'GET' && !r.path.contains('/sync')),
        isEmpty,
      );
    });
  }
}
