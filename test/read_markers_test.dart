// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/chat_list/swipe_actions.dart';
import 'package:odango/utils/privacy/read_markers.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

void main() {
  late RecordingApi api;
  late Client client;
  late Room room;

  setUp(() async {
    api = RecordingApi();
    client = await prepareTestClient(httpClient: api);
    await AppSettings.store.clear();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
    api.clear();
  });

  tearDown(() => client.dispose(closeDatabase: true));

  test('the privacy defaults are the private ones', () {
    expect(AppSettings.sendPublicReadReceipts.value, isFalse);
    expect(AppSettings.sendTypingNotifications.value, isFalse);
    expect(AppSettings.shareOnlineStatus.value, isFalse);
    expect(AppSettings.appearOffline.value, isFalse);
  });

  test(
    'public receipts off: only the private receipt leaves the client',
    () async {
      await sendReadMarker(room, r'$ev1:example.com');
      final markers = api.requests('/read_markers');
      expect(markers, hasLength(1));
      final body = markers.single.json! as Map;
      expect(body.containsKey('m.read'), isFalse);
      expect(body['m.read.private'], r'$ev1:example.com');
      expect(body['m.fully_read'], r'$ev1:example.com');
      expect(api.requests('/receipt/m.read/'), isEmpty);
    },
  );

  test('public receipts on: the public receipt is sent too', () async {
    await AppSettings.sendPublicReadReceipts.setItem(true);
    await sendReadMarker(room, r'$ev1:example.com');
    final body = api.requests('/read_markers').single.json! as Map;
    expect(body['m.read'], r'$ev1:example.com');
    expect(body['m.read.private'], r'$ev1:example.com');
  });

  test('an explicit override beats the setting', () async {
    await sendReadMarker(room, r'$ev1:example.com', public: true);
    final body = api.requests('/read_markers').single.json! as Map;
    expect(body['m.read'], r'$ev1:example.com');
  });

  test(
    'thread, receipts off: private threaded receipt, nothing else',
    () async {
      await sendReadMarker(
        room,
        r'$ev2:example.com',
        threadId: r'$root:example.com',
      );
      expect(api.requests('/read_markers'), isEmpty);
      expect(api.requests('/receipt/m.read/'), isEmpty);
      final private = api.requests('/receipt/m.read.private/');
      expect(private, hasLength(1));
      expect((private.single.json! as Map)['thread_id'], r'$root:example.com');
    },
  );

  test('thread, receipts on: public and private threaded receipts', () async {
    await AppSettings.sendPublicReadReceipts.setItem(true);
    await sendReadMarker(
      room,
      r'$ev2:example.com',
      threadId: r'$root:example.com',
    );
    expect(api.requests('/read_markers'), isEmpty);
    for (final type in ['m.read/', 'm.read.private/']) {
      final sent = api.requests('/receipt/$type');
      expect(sent, hasLength(1), reason: type);
      expect((sent.single.json! as Map)['thread_id'], r'$root:example.com');
    }
  });

  test('moveFullyRead false leaves the marker alone', () async {
    await sendReadMarker(room, r'$ev1:example.com', moveFullyRead: false);
    final body = api.requests('/read_markers').single.json! as Map;
    expect(body.containsKey('m.fully_read'), isFalse);
    expect(body['m.read.private'], r'$ev1:example.com');
  });

  for (final public in [false, true]) {
    test('swipe mark as read respects publicReceipts: $public', () async {
      room.notificationCount = 2;
      expect(room.lastEvent, isNotNull);
      expect(room.lastEvent!.status.isSynced, isTrue);
      await runSwipeAction(
        client,
        room.id,
        SwipeAction.toggleRead,
        publicReceipts: public,
      );
      final body = api.requests('/read_markers').single.json! as Map;
      expect(body.containsKey('m.read'), public);
      expect(body.containsKey('m.read.private'), isTrue);
    });
  }
}
