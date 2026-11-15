// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/reaction_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

const _me = '@test:fakeServer.notExisting';

void main() {
  late Room room;
  setUpAll(() async {
    room = Room(id: '!r:example.org', client: await prepareTestClient());
  });

  var counter = 0;
  Event reaction(String key, {String sender = '@bob:example.org'}) => Event(
    type: 'm.reaction',
    content: {
      'm.relates_to': {
        'rel_type': 'm.annotation',
        'event_id': r'$t',
        'key': key,
      },
    },
    room: room,
    eventId: '\$r${counter++}',
    senderId: sender,
    originServerTs: DateTime(2030),
  );

  test('counts, own flag and reactors', () {
    final summary = summarizeReactions([
      reaction('👍', sender: '@a:x'),
      reaction('👍', sender: _me),
      reaction('🎉', sender: '@a:x'),
    ], _me);
    expect(summary.entries.map((e) => (e.key, e.count, e.own)), [
      ('👍', 2, true),
      ('🎉', 1, false),
    ]);
    expect(summary.entries.first.reactors.length, 2);
    expect(summary.hiddenKeys, 0);
  });

  test('the same sender and key counts once', () {
    final summary = summarizeReactions([
      reaction('👍', sender: '@a:x'),
      reaction('👍', sender: '@a:x'),
    ], _me);
    expect(summary.entries.single.count, 1);
  });

  test('ties keep first seen order and the order is stable', () {
    final events = [for (var i = 0; i < 6; i++) reaction('k$i')];
    final expected = summarizeReactions(events, _me).entries.map((e) => e.key);
    expect(expected, ['k0', 'k1', 'k2', 'k3', 'k4', 'k5']);
    for (var i = 0; i < 20; i++) {
      final shuffled = [...events]..shuffle();
      final keys = summarizeReactions(shuffled, _me).entries.map((e) => e.key);
      expect(keys.toList().length, 6);
      final again = summarizeReactions(shuffled, _me).entries.map((e) => e.key);
      expect(keys, again);
    }
  });

  test('more keys than the cap are counted, not shown', () {
    final summary = summarizeReactions([
      for (var i = 0; i < 30; i++) reaction('key$i'),
    ], _me);
    expect(summary.entries.length, 24);
    expect(summary.hiddenKeys, 6);
  });

  test('a key longer than 128 characters is ignored', () {
    final summary = summarizeReactions([
      reaction('a' * 129),
      reaction('a' * 128),
    ], _me);
    expect(summary.entries.length, 1);
    expect(summary.entries.single.key.length, 128);
  });

  test('empty and missing keys are ignored', () {
    final missing = Event(
      type: 'm.reaction',
      content: const {'m.relates_to': <String, Object?>{}},
      room: room,
      eventId: r'$none',
      senderId: '@a:x',
      originServerTs: DateTime(2030),
    );
    expect(summarizeReactions([reaction(''), missing], _me).entries, isEmpty);
  });

  test('a well formed mxc key is an image, garbage never throws', () {
    final summary = summarizeReactions([
      reaction('mxc://example.org/abc'),
      reaction('mxc://%zz'),
      reaction('mxc://'),
      reaction('mxc:///x'),
      reaction('https://example.org/x.png'),
      reaction('mxc://[::1'),
      reaction('mxc://example.org/a/b'),
      reaction('mxc://example.org/'),
    ], _me);
    final byKey = {for (final e in summary.entries) e.key: e.imageUri};
    expect(byKey['mxc://example.org/abc'], Uri.parse('mxc://example.org/abc'));
    expect(byKey['mxc://%zz'], isNull);
    expect(byKey['mxc://'], isNull);
    expect(byKey['mxc:///x'], isNull);
    expect(byKey['https://example.org/x.png'], isNull);
    expect(byKey['mxc://[::1'], isNull);
    expect(byKey['mxc://example.org/a/b'], isNull);
    expect(byKey['mxc://example.org/'], isNull);
  });

  test('reactors per key are capped at 200', () {
    final summary = summarizeReactions([
      for (var i = 0; i < 250; i++) reaction('👍', sender: '@u$i:x'),
    ], _me);
    expect(summary.entries.single.count, 250);
    expect(summary.entries.single.reactors.length, 200);
  });
}
