// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

Room testChat(
  Client client,
  String id, {
  String? name,
  int unread = 0,
  int highlight = 0,
  Membership membership = Membership.join,
  String? lastBody,
  String? lastSender,
  DateTime? lastTime,
  EventStatus status = EventStatus.synced,
  Map<String, double?> tags = const {},
}) {
  final room = Room(
    id: id,
    client: client,
    membership: membership,
    notificationCount: unread,
    highlightCount: highlight,
    roomAccountData: {
      if (tags.isNotEmpty)
        'm.tag': BasicEvent(
          type: 'm.tag',
          content: {
            'tags': {
              for (final e in tags.entries)
                e.key: <String, Object?>{'order': ?e.value},
            },
          },
        ),
    },
  );
  if (name != null) {
    room.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': name},
        room: room,
        eventId: '\$name$id',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
  }
  if (lastBody != null) {
    room.lastEvent = Event(
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': lastBody},
      room: room,
      eventId: '\$last$id',
      senderId: lastSender ?? '@anna:example.org',
      originServerTs: lastTime ?? DateTime.now(),
      status: status,
    );
  }
  return room;
}
