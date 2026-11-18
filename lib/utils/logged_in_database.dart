// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The database of [client] while it is signed in. After a logout the SDK has
/// cleared the database, so a late write (a draft saved while the chat page
/// closes, a queued persist) must not put plaintext back into it.
DatabaseApi loggedInDatabase(Client client) {
  if (!client.isLogged()) throw StateError('The client is signed out');
  return client.database;
}
