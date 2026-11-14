// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

Room testSpace(
  Client client,
  List<String> children, {
  String id = '!space:example.org',
  Membership membership = Membership.join,
  String? name,
}) {
  final space = Room(id: id, client: client, membership: membership);
  space.setState(
    Event(
      type: EventTypes.RoomCreate,
      stateKey: '',
      content: {'type': RoomCreationTypes.mSpace},
      room: space,
      eventId: '\$create',
      senderId: '@admin:example.org',
      originServerTs: DateTime(2030),
    ),
  );
  if (name != null) {
    space.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': name},
        room: space,
        eventId: '\$name',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
  }
  for (final child in children) {
    space.setState(
      Event(
        type: EventTypes.SpaceChild,
        stateKey: child,
        content: {
          'via': ['example.org'],
        },
        room: space,
        eventId: '\$$child',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2030),
      ),
    );
  }
  return space;
}

Room testSpaceChild(
  Client client,
  String id, {
  int unread = 0,
  Membership? membership,
  List<String> tags = const [],
}) => Room(
  id: id,
  client: client,
  membership: membership ?? Membership.join,
  notificationCount: unread,
  roomAccountData: {
    if (tags.isNotEmpty)
      'm.tag': BasicEvent(
        type: 'm.tag',
        content: {
          'tags': {for (final tag in tags) tag: <String, Object?>{}},
        },
      ),
  },
);
