// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/new_message/contact_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';

void main() {
  const me = '@me:example.org';

  ContactSource source(String id, DateTime activity, {String? name}) =>
      ContactSource(userId: id, name: name ?? id, lastActivity: activity);

  CachedPresence presence(
    String id, {
    PresenceType type = PresenceType.offline,
    DateTime? seen,
    String? status,
  }) => CachedPresence.fromJson({
    'user_id': id,
    'presence': type.name,
    'last_active_timestamp': ?seen?.millisecondsSinceEpoch,
    'status_msg': ?status,
  });

  test('those seen last come first, then by chat activity', () {
    final list = ContactList.build(
      [
        source('@a:example.org', DateTime(2031, 1, 1)),
        source('@b:example.org', DateTime(2031, 1, 5)),
        source('@c:example.org', DateTime(2031, 1, 3)),
      ],
      presences: {
        '@a:example.org': presence(
          '@a:example.org',
          seen: DateTime(2031, 2, 1),
        ),
        '@c:example.org': presence(
          '@c:example.org',
          seen: DateTime(2031, 3, 1),
        ),
      },
      ownUserId: me,
    );
    expect(list.map((e) => e.userId), [
      '@c:example.org',
      '@a:example.org',
      '@b:example.org',
    ]);
  });

  test('without presence the newest chat first', () {
    final list = ContactList.build(
      [
        source('@a:example.org', DateTime(2031, 1, 1)),
        source('@b:example.org', DateTime(2031, 1, 5)),
      ],
      presences: const {},
      ownUserId: me,
    );
    expect(list.map((e) => e.userId), ['@b:example.org', '@a:example.org']);
  });

  test('the own user and repeats are left out', () {
    final list = ContactList.build(
      [
        source(me, DateTime(2031)),
        source('@a:example.org', DateTime(2031)),
        source('@a:example.org', DateTime(2032)),
      ],
      presences: const {},
      ownUserId: me,
    );
    expect(list.map((e) => e.userId), ['@a:example.org']);
  });

  test('online only when the cached presence says online', () {
    final list = ContactList.build(
      [
        source('@a:example.org', DateTime(2031)),
        source('@b:example.org', DateTime(2031)),
        source('@c:example.org', DateTime(2031)),
      ],
      presences: {
        '@a:example.org': presence('@a:example.org', type: PresenceType.online),
        '@b:example.org': presence(
          '@b:example.org',
          type: PresenceType.unavailable,
        ),
      },
      ownUserId: me,
    );
    final online = {for (final e in list) e.userId: e.online};
    expect(online, {
      '@a:example.org': true,
      '@b:example.org': false,
      '@c:example.org': false,
    });
  });

  test('status text is cleaned and cut', () {
    final list = ContactList.build(
      [
        source('@a:example.org', DateTime(2031)),
        source('@b:example.org', DateTime(2031)),
        source('@c:example.org', DateTime(2031)),
      ],
      presences: {
        '@a:example.org': presence(
          '@a:example.org',
          status: 'a\u202Eb\u200Bc\nd',
        ),
        '@b:example.org': presence('@b:example.org', status: 'x' * 1000),
        '@c:example.org': presence('@c:example.org', status: '   '),
      },
      ownUserId: me,
    );
    final status = {for (final e in list) e.userId: e.status};
    expect(status['@a:example.org'], isNot(contains('\u202E')));
    expect(status['@a:example.org'], isNot(contains('\u200B')));
    expect(status['@a:example.org'], isNot(contains('\n')));
    expect(
      status['@b:example.org']!.characters.length,
      ContactList.maxStatusChars,
    );
    expect(status['@c:example.org'], isNull);
  });

  test('names are cleaned', () {
    final list = ContactList.build(
      [source('@a:example.org', DateTime(2031), name: 'Mal\u202Elory\u200B')],
      presences: const {},
      ownUserId: me,
    );
    expect(list.single.name, isNot(contains('\u202E')));
    expect(list.single.name, isNot(contains('\u200B')));
  });

  test('at most 200 contacts', () {
    final list = ContactList.build(
      [
        for (var n = 0; n < 500; n++)
          source(
            '@u$n:example.org',
            DateTime(2031, 1, 1).add(Duration(minutes: n)),
          ),
      ],
      presences: const {},
      ownUserId: me,
    );
    expect(list.length, ContactList.maxContacts);
    expect(list.first.userId, '@u499:example.org');
  });
}
