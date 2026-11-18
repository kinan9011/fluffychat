// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

const legacySpaceHierarchyCachePrefix = 'spaces_history_cache';

/// Older versions kept the names and topics of the rooms of every space that
/// was opened in the shared preferences. Nothing writes them any more: this
/// removes what is left. Returns how many entries were removed.
Future<int> purgeLegacySpaceHierarchyCache(SharedPreferences store) async {
  final keys = store
      .getKeys()
      .where((key) => key.startsWith(legacySpaceHierarchyCachePrefix))
      .toList();
  for (final key in keys) {
    await store.remove(key);
  }
  return keys.length;
}
