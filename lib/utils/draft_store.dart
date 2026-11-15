// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

/// Access path to the chat drafts. Key and values are exactly what the chat
/// page always stored (`draft_<roomId>` in the shared preferences); this class
/// only tells the chat list when a draft changed. It never logs.
class DraftStore {
  DraftStore(this._prefs);

  final SharedPreferences _prefs;

  static String keyFor(String roomId) => 'draft_$roomId';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  String? read(String roomId) => _prefs.getString(keyFor(roomId));

  /// The draft as the chat list shows it: nothing for a blank draft.
  String? readForDisplay(String roomId) {
    final draft = read(roomId);
    return draft == null || draft.trim().isEmpty ? null : draft;
  }

  Future<void> write(String roomId, String text) async {
    await _prefs.setString(keyFor(roomId), text);
    revision.value++;
  }

  Future<void> remove(String roomId) async {
    await _prefs.remove(keyFor(roomId));
    revision.value++;
  }

  static String preview(String draft) => draft
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .characters
      .take(120)
      .toString();
}
