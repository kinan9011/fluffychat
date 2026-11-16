// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/format_state.dart';
import 'package:fluffychat/utils/rich_text/html_serializer.dart';
import 'package:fluffychat/utils/rich_text/outgoing_message.dart';
import 'package:fluffychat/utils/rich_text/rich_mentions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

Map<String, Object?>? sentMentions() {
  final bodies = FakeMatrixApi.calledEndpoints.entries
      .where((e) => e.key.contains('/send/m.room.message/'))
      .expand((e) => e.value)
      .toList();
  expect(bodies, hasLength(1));
  final body = bodies.single;
  final decoded = body is String ? jsonDecode(body) as Map : body as Map;
  return decoded['m.mentions'] as Map<String, Object?>?;
}

void main() {
  group('planOutgoing', () {
    test('no formatting is plain', () {
      expect(planOutgoing('hello', FormatState()), isA<PlainOutgoing>());
    });

    test('ranges make it rich', () {
      final plan = planOutgoing(
        'hello',
        FormatState(ranges: const [FormatRange(0, 5, RangeKind.bold)]),
      );
      expect(plan, isA<RichOutgoing>());
      expect(
        (plan as RichOutgoing).message.formattedBody,
        '<strong>hello</strong>',
      );
      expect(plan.plainText, 'hello');
    });

    test('block intent with a prefix is rich', () {
      final plan = planOutgoing('- a\n- b', FormatState(richIntent: true));
      expect(
        (plan as RichOutgoing).message.formattedBody,
        '<ul><li>a</li><li>b</li></ul>',
      );
    });

    test('intent without any formatting stays plain', () {
      expect(
        planOutgoing('just text', FormatState(richIntent: true)),
        isA<PlainOutgoing>(),
      );
    });

    test(
      'the whole event stays inside the budget, edits and E2EE count more',
      () {
        FormatState bold(int n) =>
            FormatState(ranges: [FormatRange(0, n, RangeKind.bold)]);
        final small = 'é' * 11000;
        expect(planOutgoing(small, bold(small.length)), isA<RichOutgoing>());
        expect(
          () => planOutgoing(small, bold(small.length), encrypted: true),
          throwsA(isA<RichTextTooLong>()),
        );
        expect(
          () => planOutgoing(small, bold(small.length), edit: true),
          throwsA(isA<RichTextTooLong>()),
        );
        const fits = 5000;
        final text = 'é' * fits;
        expect(
          planOutgoing(text, bold(fits), edit: true, encrypted: true),
          isA<RichOutgoing>(),
        );
        final big = 'é' * 6000;
        expect(
          () =>
              planOutgoing(big, bold(big.length), edit: true, encrypted: true),
          throwsA(isA<RichTextTooLong>()),
        );
      },
    );

    test('a command never goes the rich way', () {
      final state = FormatState(
        ranges: const [FormatRange(0, 5, RangeKind.bold)],
        richIntent: true,
      );
      expect(planOutgoing('/me waves', state), isA<PlainOutgoing>());
      expect(planOutgoing('/plain *x*', state), isA<PlainOutgoing>());
    });

    test('a slash that is not a command is rich again', () {
      final state = FormatState(
        ranges: const [FormatRange(2, 5, RangeKind.bold)],
      );
      expect(planOutgoing('a /bold', state), isA<RichOutgoing>());
    });

    test('too long throws', () {
      final state = FormatState(
        ranges: [const FormatRange(0, 5, RangeKind.bold)],
      );
      expect(
        () => planOutgoing('<' * 15000, state..richIntent = true),
        throwsA(isA<RichTextTooLong>()),
      );
    });
  });

  group('richMentions parity with the SDK', () {
    const bodies = [
      'hi @room look',
      'hello @alice:example.org and @bob:example.org',
      'hello @[Display Name] there',
      'nothing to see',
      '@alice:example.org @alice:example.org',
      'me @test:fakeServer.notExisting me',
      '@room @room',
      'mail a@b.org not a mention',
      '@x',
      'trailing @',
      '@[unterminated',
      '@alice:example.org, @bob:example.org.',
    ];
    for (final body in bodies) {
      test(body, () async {
        final client = await prepareTestClient();
        final room = Room(id: '!localpart:server.abc', client: client);
        FakeMatrixApi.calledEndpoints.clear();
        try {
          await room.sendTextEvent(
            body,
            parseMarkdown: false,
            parseCommands: false,
          );
        } catch (_) {}
        final expected = sentMentions();
        final ours = richMentions(
          plainText: body,
          resolve: room.getMention,
          ownUserId: client.userID,
        );
        expect(ours, expected);
      });
    }

    test('the replied-to sender is added', () {
      expect(
        richMentions(
          plainText: 'x',
          resolve: (_) => null,
          ownUserId: '@me:example.org',
          repliedToSender: '@alice:example.org',
        ),
        {
          'user_ids': ['@alice:example.org'],
        },
      );
    });

    test('mentions are read from the text without markers', () {
      expect(
        richMentions(
          plainText: 'ping @alice:example.org',
          resolve: (_) => null,
          ownUserId: null,
        ),
        {
          'user_ids': ['@alice:example.org'],
        },
      );
      expect(
        richMentions(
          plainText: 'ping **@alice:example.org**',
          resolve: (_) => null,
          ownUserId: null,
        ),
        isNot(
          equals({
            'user_ids': ['@alice:example.org'],
          }),
        ),
      );
      expect(
        '@alice:example.org'.isValidMatrixIdStrict(strictDomainCheck: true),
        isTrue,
      );
    });
  });
}
