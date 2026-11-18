// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

Room searchRoom(
  Client client,
  String id, {
  bool encrypted = true,
  Membership membership = Membership.join,
}) {
  final room = Room(id: id, client: client, membership: membership);
  if (encrypted) {
    room.setState(
      Event(
        type: EventTypes.Encryption,
        stateKey: '',
        content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
        room: room,
        eventId: r'$enc:example.org',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2025),
      ),
    );
  }
  return room;
}

Event searchEvent(
  Room room,
  String eventId, {
  Object? body = 'hello world',
  String msgtype = MessageTypes.Text,
  String type = EventTypes.Message,
  String senderId = '@alice:example.org',
  DateTime? at,
  EventStatus status = EventStatus.synced,
  Map<String, Object?> extra = const {},
}) => Event(
  type: type,
  content: {'msgtype': msgtype, 'body': ?body, ...extra},
  room: room,
  eventId: eventId,
  senderId: senderId,
  originServerTs: at ?? DateTime.now().subtract(const Duration(hours: 1)),
  status: status,
);
