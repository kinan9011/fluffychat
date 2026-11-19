// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/scheduling/scheduled_content.dart';
import 'package:odango/utils/scheduling/silent_notification.dart';

import 'utils/test_client.dart';

void main() {
  late Room room;

  setUpAll(() async {
    final client = await prepareTestClient(clientName: 'silent');
    room = Room(id: '!a:example.org', client: client);
  });

  Event event({
    String type = EventTypes.Message,
    Object? silent = true,
    Map<String, Object?> extra = const {},
  }) => Event(
    type: type,
    content: {
      'msgtype': 'm.text',
      'body': 'hi',
      ScheduledContent.silentKey: ?silent,
      ...extra,
    },
    room: room,
    eventId: r'$e:example.org',
    senderId: '@bob:example.org',
    originServerTs: DateTime(2025),
  );

  test('a flagged plain message is silent', () {
    expect(notifySilently(event(), highlight: false), isTrue);
  });

  test('a highlight is never silenced', () {
    expect(notifySilently(event(), highlight: true), isFalse);
  });

  test('only a message can be silenced', () {
    for (final type in [
      EventTypes.Encrypted,
      EventTypes.Sticker,
      EventTypes.Reaction,
      EventTypes.CallInvite,
      'org.matrix.msc4075.rtc.notification',
      'm.rtc.notification',
      'org.matrix.msc3401.call.member',
    ]) {
      expect(
        notifySilently(event(type: type), highlight: false),
        isFalse,
        reason: type,
      );
    }
  });

  test('only the boolean true counts', () {
    for (final value in <Object?>[
      false,
      'true',
      1,
      'yes',
      null,
      {'a': 1},
    ]) {
      expect(
        notifySilently(event(silent: value), highlight: false),
        isFalse,
        reason: '$value',
      );
    }
  });

  test('a message without the flag is loud', () {
    expect(notifySilently(event(silent: null), highlight: false), isFalse);
  });

  test('a flag nested in the content does not count', () {
    expect(
      notifySilently(
        event(
          silent: null,
          extra: {
            'm.new_content': {ScheduledContent.silentKey: true},
          },
        ),
        highlight: false,
      ),
      isFalse,
    );
  });
}
