// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

typedef StoredEventReader = Future<List<Event>> Function(Room room, int limit);

/// The newest events of a room that the SDK already holds in its (encrypted)
/// database, decrypted when the keys were there. No network request.
Future<List<Event>> readStoredEvents(
  Client client,
  Room room,
  int limit,
) async {
  try {
    return await client.database.getEventList(room, start: 0, limit: limit);
  } catch (_) {
    Logs().w('[Search] stored events unavailable');
    return const [];
  }
}
