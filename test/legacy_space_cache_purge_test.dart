// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/spaces/legacy_cache_purge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'spaces_history_cache!a:example.org': ['{"name":"Private room"}'],
      'spaces_history_cache!b:example.org': ['{"name":"Other"}'],
      'draft_unrelated': 'keep',
      'com.swovo.odango.search.server': 'other.example',
      'spaces_history': 'not the cache but similar',
    });
    store = await SharedPreferences.getInstance();
  });

  test('every cached hierarchy is removed', () async {
    final removed = await purgeLegacySpaceHierarchyCache(store);
    expect(removed, 2);
    expect(
      store.getKeys().where((k) => k.startsWith('spaces_history_cache')),
      isEmpty,
    );
  });

  test('other keys are untouched', () async {
    await purgeLegacySpaceHierarchyCache(store);
    expect(store.getString('draft_unrelated'), 'keep');
    expect(store.getString('com.swovo.odango.search.server'), 'other.example');
    expect(store.getString('spaces_history'), 'not the cache but similar');
  });

  test('a second run finds nothing', () async {
    await purgeLegacySpaceHierarchyCache(store);
    expect(await purgeLegacySpaceHierarchyCache(store), 0);
  });

  test('no private room name is left anywhere in the store', () async {
    await purgeLegacySpaceHierarchyCache(store);
    for (final key in store.getKeys()) {
      expect(store.get(key).toString(), isNot(contains('Private room')));
    }
  });
}
