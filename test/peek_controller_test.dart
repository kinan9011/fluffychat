// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';

import 'package:fluffychat/utils/chat_list/peek_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

import 'utils/test_client.dart';

class _SpyTimeline extends Timeline {
  final List<String> calls;
  int cancelled = 0;

  _SpyTimeline({
    required super.room,
    required super.chunk,
    required super.onUpdate,
    required this.calls,
  });

  @override
  void cancelSubscriptions() {
    cancelled++;
    super.cancelSubscriptions();
  }

  @override
  Future<void> setReadMarker({String? eventId, bool? public}) async =>
      calls.add('timeline.setReadMarker');

  @override
  void requestKeys({
    bool tryOnlineBackup = true,
    bool onlineKeyBackupOnly = true,
  }) => calls.add('timeline.requestKeys');

  @override
  Future<void> requestHistory({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async => calls.add('timeline.requestHistory');

  @override
  Future<void> requestFuture({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async => calls.add('timeline.requestFuture');
}

class _SpyRoom extends Room {
  final List<String> calls = [];
  final List<Event> fixture;
  Completer<void>? gate;
  _SpyTimeline? last;

  _SpyRoom(Client client, this.fixture)
    : super(id: '!peek:x', client: client, membership: Membership.join);

  @override
  Future<Timeline> getTimeline({
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function(int insertID)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async {
    calls.add('getTimeline');
    await gate?.future;
    return last = _SpyTimeline(
      room: this,
      chunk: TimelineChunk(events: List.of(fixture)),
      onUpdate: onUpdate,
      calls: calls,
    );
  }

  @override
  Future<void> setReadMarker(
    String? eventId, {
    String? mRead,
    bool? public,
  }) async => calls.add('room.setReadMarker');

  @override
  Future<void> markUnread(bool unread) async => calls.add('room.markUnread');

  @override
  Future<void> setTyping(bool isTyping, {int? timeout}) async =>
      calls.add('room.setTyping');

  @override
  Future<void> postReceipt(
    String eventId, {
    ReceiptType type = ReceiptType.mRead,
  }) async => calls.add('room.postReceipt');

  List<String> get signals => calls
      .where((call) => call != 'getTimeline' && call != 'cancelSubscriptions')
      .toList();
}

void main() {
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
  });

  _SpyRoom spyRoom() {
    final room = _SpyRoom(client, <Event>[]);
    final events = <Event>[
      for (var i = 0; i < 30; i++)
        Event(
          type: EventTypes.Message,
          content: {'msgtype': MessageTypes.Text, 'body': 'm$i'},
          room: room,
          eventId: '\$e$i',
          senderId: '@anna:example.org',
          originServerTs: DateTime(2030, 1, 1, 0, 0, 30 - i),
        ),
    ];
    events[3] = Event(
      type: EventTypes.Reaction,
      content: {
        'm.relates_to': {
          'rel_type': 'm.annotation',
          'event_id': '\$e1',
          'key': 'x',
        },
      },
      room: room,
      eventId: '\$hidden',
      senderId: '@anna:example.org',
      originServerTs: DateTime(2030),
    );
    events[5] = Event(
      type: EventTypes.Encrypted,
      content: {
        'algorithm': 'm.megolm.v1.aes-sha2',
        'session_id': 's',
        'sender_key': 'k',
        'ciphertext': 'c',
        'can_request_session': true,
      },
      room: room,
      eventId: '\$enc',
      senderId: '@anna:example.org',
      originServerTs: DateTime(2030),
    );
    room.fixture.addAll(events);
    return room;
  }

  test('open lists the newest 20 visible events, newest first', () async {
    final room = spyRoom();
    final controller = PeekController(room);
    await controller.open();
    final events = controller.events.value;
    expect(events.length, 20);
    expect(events.first.eventId, '\$e0');
    expect(events.any((event) => event.eventId == '\$hidden'), isFalse);
    expect(room.signals, isEmpty);
    controller.close();
  });

  test('a timeline update republishes the list', () async {
    final room = spyRoom();
    final controller = PeekController(room);
    await controller.open();
    room.last!.chunk.events.insert(
      0,
      Event(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'new'},
        room: room,
        eventId: '\$new',
        senderId: '@anna:example.org',
        originServerTs: DateTime(2031),
      ),
    );
    room.last!.onUpdate!();
    expect(controller.events.value.first.eventId, '\$new');
    expect(controller.events.value.length, 20);
    expect(room.signals, isEmpty);
    controller.close();
  });

  test('close cancels the timeline subscriptions and disposes', () async {
    final room = spyRoom();
    final controller = PeekController(room);
    await controller.open();
    controller.close();
    expect(room.last!.cancelled, 1);
    expect(
      () => controller.events.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
    expect(room.signals, isEmpty);
  });

  test('closing twice cancels once', () async {
    final room = spyRoom();
    final controller = PeekController(room);
    await controller.open();
    controller
      ..close()
      ..close();
    expect(room.last!.cancelled, 1);
  });

  test('closing before the timeline arrives publishes nothing', () async {
    final room = spyRoom()..gate = Completer<void>();
    final controller = PeekController(room);
    final opening = controller.open();
    controller.close();
    room.gate!.complete();
    await opening;
    expect(room.last!.cancelled, 1);
    expect(room.signals, isEmpty);
  });

  test('the limit is honoured', () async {
    final room = spyRoom();
    final controller = PeekController(room, limit: 5);
    await controller.open();
    expect(controller.events.value.length, 5);
    controller.close();
  });
}
