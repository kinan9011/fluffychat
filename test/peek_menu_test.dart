// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat_list/peek_menu.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  test(
    'an entry only runs while the room is in the state it was shown for',
    () {
      final unread = testChat(client, '!pm1:x', name: 'a', unread: 2);
      expect(peekStillShown(unread, PeekMenuItem.toggleRead, true), isTrue);
      expect(peekStillShown(unread, PeekMenuItem.toggleRead, false), isFalse);
      final read = testChat(client, '!pm2:x', name: 'b');
      expect(peekStillShown(read, PeekMenuItem.toggleRead, false), isTrue);
      expect(
        peekStillShown(read, PeekMenuItem.toggleRead, true),
        isFalse,
        reason: '"Mark as read" must never mark a read chat unread',
      );
    },
  );

  test('pin, mute and archive follow the same rule', () {
    final plain = testChat(client, '!pm3:x', name: 'c');
    final pinned = testChat(
      client,
      '!pm4:x',
      name: 'd',
      tags: {'m.favourite': 0.5},
    );
    final archived = testChat(
      client,
      '!pm5:x',
      name: 'e',
      tags: {'com.swovo.odango.archived': null},
    );
    expect(peekStillShown(plain, PeekMenuItem.pin, false), isTrue);
    expect(peekStillShown(plain, PeekMenuItem.pin, true), isFalse);
    expect(peekStillShown(pinned, PeekMenuItem.pin, true), isTrue);
    expect(peekStillShown(archived, PeekMenuItem.archive, true), isTrue);
    expect(peekStillShown(plain, PeekMenuItem.archive, true), isFalse);
    expect(peekStillShown(plain, PeekMenuItem.mute, false), isTrue);
    expect(peekStillShown(plain, PeekMenuItem.mute, true), isFalse);
  });

  test('leaving and more options do not depend on the state', () {
    final room = testChat(client, '!pm6:x', name: 'f');
    for (final shown in [true, false]) {
      expect(peekStillShown(room, PeekMenuItem.leave, shown), isTrue);
      expect(peekStillShown(room, PeekMenuItem.more, shown), isTrue);
    }
  });
}
