// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';
import 'package:odango/utils/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const legacyDraftKeyPrefix = 'draft_';
const _maxScannedKeys = 1000;

Future<int>? _running;

/// Moves the plaintext `draft_<roomId>` preferences of the old composer into
/// the encrypted database of the account that joined the room. A preference is
/// deleted only after the stored copy reads back; a failure keeps it for the
/// next start. A room joined by several accounts goes to the first one (the
/// old key never said which account typed the draft). Drafts of rooms no
/// account knows are kept until every logged account has synced once. Returns the number of
/// drafts moved.
Future<int> migrateLegacyDrafts({
  required SharedPreferences prefs,
  required List<Client> clients,
  @visibleForTesting DraftStore Function(Client client) storeOf = DraftStore.of,
}) => _running ??= _migrate(
  prefs,
  clients,
  storeOf,
).whenComplete(() => _running = null);

Future<int> _migrate(
  SharedPreferences prefs,
  List<Client> clients,
  DraftStore Function(Client client) storeOf,
) async {
  final logged = clients.where((client) => client.isLogged()).toList();
  await Future.wait([
    for (final client in logged) ...[
      (client.roomsLoading ?? Future<void>.value()).catchError((_) {}),
      storeOf(client).ready,
    ],
  ]);
  var moved = 0;
  while (true) {
    final unsynced = logged.where((client) => client.prevBatch == null);
    moved += await _movePass(
      prefs,
      logged,
      storeOf,
      dropOwnerless: unsynced.isEmpty,
    );
    if (unsynced.isEmpty || _legacyKeys(prefs).isEmpty) return moved;
    await Future.wait([
      for (final client in logged)
        client.prevBatch == null
            ? client.onSync.stream.first
            : Future<SyncUpdate?>.value(),
    ]);
  }
}

List<String> _legacyKeys(SharedPreferences prefs) => prefs
    .getKeys()
    .where((key) => key.startsWith(legacyDraftKeyPrefix))
    .take(_maxScannedKeys)
    .toList();

Future<int> _movePass(
  SharedPreferences prefs,
  List<Client> logged,
  DraftStore Function(Client client) storeOf, {
  required bool dropOwnerless,
}) async {
  var moved = 0;
  for (final key in _legacyKeys(prefs)) {
    final value = prefs.get(key);
    final roomId = key.substring(legacyDraftKeyPrefix.length);
    if (value is! String ||
        !DraftStore.isRoomId(roomId) ||
        value.trim().isEmpty) {
      await prefs.remove(key);
      continue;
    }
    final owner = logged.firstWhereOrNull(
      (client) => client.getRoomById(roomId)?.membership == Membership.join,
    );
    if (owner == null) {
      if (dropOwnerless) await prefs.remove(key);
      continue;
    }
    final text = value.characters.take(DraftStore.maxDraftChars).toString();
    if (await storeOf(owner).importLegacy(roomId, text)) {
      await prefs.remove(key);
      moved++;
    }
  }
  return moved;
}
