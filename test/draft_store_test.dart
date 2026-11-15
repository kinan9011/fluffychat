// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late DraftStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = DraftStore(prefs);
  });

  test('the key is the one the chat page always used', () {
    expect(DraftStore.keyFor('!a:b'), 'draft_!a:b');
  });

  test('storage is byte-identical to the old raw preferences calls', () async {
    await store.write('!a:b', '  hello\nworld  ');
    expect(prefs.getString('draft_!a:b'), '  hello\nworld  ');
    expect(prefs.getKeys(), {'draft_!a:b'});
    await store.write('!a:b', '');
    expect(prefs.getString('draft_!a:b'), '', reason: 'cleared input is kept');
    await store.remove('!a:b');
    expect(prefs.getKeys(), isEmpty);
  });

  test('a value stored by the old code path is read back', () async {
    await prefs.setString('draft_!a:b', 'x');
    expect(store.read('!a:b'), 'x');
    expect(store.readForDisplay('!a:b'), 'x');
  });

  test('a value written here is readable by the old code path', () async {
    await store.write('!a:b', 'hi');
    expect(prefs.getString('draft_!a:b'), 'hi');
  });

  test('a blank draft is not shown', () async {
    await store.write('!a:b', ' \n ');
    expect(store.read('!a:b'), ' \n ');
    expect(store.readForDisplay('!a:b'), isNull);
    expect(store.readForDisplay('!missing:b'), isNull);
  });

  test('the revision moves on write and on remove', () async {
    final start = DraftStore.revision.value;
    await store.write('!a:b', 'x');
    expect(DraftStore.revision.value, start + 1);
    await store.remove('!a:b');
    expect(DraftStore.revision.value, start + 2);
  });

  test('preview collapses whitespace and cuts at 120 clusters', () {
    expect(DraftStore.preview('a\n\n b   c'), 'a b c');
    expect(DraftStore.preview('a' * 200).length, 120);
    final family = '\u{1F468}‍\u{1F469}‍\u{1F467}' * 130;
    expect(DraftStore.preview(family), '\u{1F468}‍\u{1F469}‍\u{1F467}' * 120);
  });

  test('draft text never reaches the log', () async {
    Logs().outputEvents.clear();
    await store.write('!a:b', 'SENTINEL-DRAFT-7f3');
    store.read('!a:b');
    store.readForDisplay('!a:b');
    DraftStore.preview('SENTINEL-DRAFT-7f3');
    await store.remove('!a:b');
    for (final event in Logs().outputEvents) {
      expect(event.title, isNot(contains('SENTINEL')));
      expect('${event.exception}', isNot(contains('SENTINEL')));
      expect('${event.stackTrace}', isNot(contains('SENTINEL')));
    }
  });

  test('the chat page reaches drafts only through the store', () {
    final source = File('lib/pages/chat/chat.dart').readAsStringSync();
    expect(source, isNot(contains("'draft_")));
    expect(source, contains('DraftStore('));
  });
}
