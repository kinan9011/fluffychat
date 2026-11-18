// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/search/index_policy.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room encrypted;
  late Room plain;
  const me = '@test:fakeServer.notExisting';

  setUpAll(() async {
    client = await prepareTestClient();
    encrypted = searchRoom(client, '!enc:example.org');
    plain = searchRoom(client, '!plain:example.org', encrypted: false);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  const id = r'$e1:example.org';

  test('a text message of an encrypted room becomes an entry', () {
    final entry = IndexPolicy.fromEvent(
      searchEvent(encrypted, id, body: 'Hello  WORLD'),
      ownUserId: me,
    )!;
    expect(entry.roomId, '!enc:example.org');
    expect(entry.eventId, id);
    expect(entry.senderId, '@alice:example.org');
    expect(entry.kind, SearchKind.text);
    expect(entry.text, 'Hello WORLD');
    expect(entry.hasLink, isFalse);
    expect(entry.mentionsMe, isFalse);
  });

  test('unencrypted rooms are never indexed', () {
    expect(
      IndexPolicy.fromEvent(searchEvent(plain, id), ownUserId: me),
      isNull,
    );
  });

  test('redacted, pending and failed events are not indexed', () {
    final redacted = searchEvent(encrypted, id)
      ..setRedactionEvent(
        searchEvent(encrypted, r'$r:example.org', type: EventTypes.Redaction),
      );
    expect(IndexPolicy.fromEvent(redacted, ownUserId: me), isNull);
    for (final status in [EventStatus.sending, EventStatus.error]) {
      expect(
        IndexPolicy.fromEvent(
          searchEvent(encrypted, id, status: status),
          ownUserId: me,
        ),
        isNull,
        reason: '$status',
      );
    }
  });

  test('an edit is no entry of its own but is read by editOf', () {
    final edit = searchEvent(
      encrypted,
      r'$edit:example.org',
      body: '* new',
      extra: {
        'm.new_content': {'msgtype': 'm.text', 'body': 'New TEXT'},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': id},
      },
    );
    expect(IndexPolicy.fromEvent(edit, ownUserId: me), isNull);
    final parsed = IndexPolicy.editOf(edit)!;
    expect(parsed.targetId, id);
    expect(parsed.text, 'New TEXT');
  });

  test('editOf ignores malformed edits', () {
    for (final extra in <Map<String, Object?>>[
      {
        'm.new_content': 'x',
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': id},
      },
      {
        'm.new_content': {'body': 5},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': id},
      },
      {
        'm.new_content': {'body': 'x'},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': 'nope'},
      },
      {
        'm.new_content': {'body': '   '},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': id},
      },
      {
        'm.new_content': {'body': 'x'},
        'm.relates_to': {'rel_type': 'm.annotation', 'event_id': id},
      },
      {'m.relates_to': 'x'},
    ]) {
      expect(
        IndexPolicy.editOf(
          searchEvent(encrypted, r'$ed:example.org', extra: extra),
        ),
        isNull,
        reason: '$extra',
      );
    }
  });

  test('redactionTarget needs a redaction with a valid id', () {
    Event redaction(String? target) => Event(
      type: EventTypes.Redaction,
      content: {},
      room: encrypted,
      eventId: r'$r:example.org',
      senderId: '@alice:example.org',
      originServerTs: DateTime.now(),
      redacts: target,
    );
    expect(IndexPolicy.redactionTarget(redaction(id)), id);
    expect(IndexPolicy.redactionTarget(redaction('bad')), isNull);
    expect(IndexPolicy.redactionTarget(redaction(null)), isNull);
    expect(IndexPolicy.redactionTarget(searchEvent(encrypted, id)), isNull);
  });

  test('message kinds', () {
    SearchKind? kind(String msgtype, {Map<String, Object?> extra = const {}}) =>
        IndexPolicy.fromEvent(
          searchEvent(
            encrypted,
            id,
            msgtype: msgtype,
            body: 'f.bin',
            extra: extra,
          ),
          ownUserId: me,
        )?.kind;
    expect(kind('m.text'), SearchKind.text);
    expect(kind('m.notice'), SearchKind.text);
    expect(kind('m.emote'), SearchKind.text);
    expect(kind('m.image'), SearchKind.image);
    expect(kind('m.video'), SearchKind.video);
    expect(kind('m.file'), SearchKind.file);
    expect(kind('m.audio'), SearchKind.audio);
    expect(
      kind('m.audio', extra: {'org.matrix.msc3245.voice': <String, Object?>{}}),
      SearchKind.voice,
    );
    expect(kind('m.location'), isNull);
    expect(kind('com.example.weird'), isNull);
  });

  test('stickers and calls are not indexed', () {
    expect(
      IndexPolicy.fromEvent(
        searchEvent(encrypted, id, type: EventTypes.Sticker),
        ownUserId: me,
      ),
      isNull,
    );
  });

  test('a poll is indexed by its question', () {
    final poll = searchEvent(
      encrypted,
      id,
      body: null,
      type: PollEventContent.startType,
      extra: {
        PollEventContent.startType: {
          'question': {PollEventContent.mTextJsonKey: 'Lunch at NOON?'},
          'answers': [
            {'id': 'a', PollEventContent.mTextJsonKey: 'Pizza'},
            {'id': 'b', PollEventContent.mTextJsonKey: 'Soup'},
          ],
          'kind': 'org.matrix.msc3381.poll.disclosed',
          'max_selections': 1,
        },
      },
    );
    final entry = IndexPolicy.fromEvent(poll, ownUserId: me)!;
    expect(entry.kind, SearchKind.poll);
    expect(entry.text, 'Lunch at NOON?');
  });

  test('links are flagged', () {
    IndexPolicy.fromEvent(
      searchEvent(encrypted, id, body: 'see HTTPS://example.org/x'),
      ownUserId: me,
    )!;
    expect(
      IndexPolicy.fromEvent(
        searchEvent(encrypted, id, body: 'see HTTPS://example.org/x'),
        ownUserId: me,
      )!.hasLink,
      isTrue,
    );
  });

  group('mentions', () {
    bool mentioned(Map<String, Object?> extra, {String body = 'hi'}) =>
        IndexPolicy.fromEvent(
          searchEvent(encrypted, id, body: body, extra: extra),
          ownUserId: me,
        )!.mentionsMe;

    test('m.mentions user ids', () {
      expect(
        mentioned({
          'm.mentions': {
            'user_ids': [me],
          },
        }),
        isTrue,
      );
    });

    test('m.mentions room', () {
      expect(
        mentioned({
          'm.mentions': {'room': true},
        }),
        isTrue,
      );
    });

    test('the user id in the body', () {
      expect(mentioned({}, body: 'ping ${me.toUpperCase()}'), isTrue);
    });

    test('no mention', () {
      expect(mentioned({}), isFalse);
      expect(
        mentioned({
          'm.mentions': {
            'user_ids': ['@other:example.org'],
          },
        }),
        isFalse,
      );
    });

    test('hostile m.mentions never throw', () {
      for (final value in <Object?>[
        'x',
        5,
        [1, 2],
        {'user_ids': 'x'},
        {
          'user_ids': [1, null, {}],
          'room': 'yes',
        },
      ]) {
        expect(mentioned({'m.mentions': value}), isFalse, reason: '$value');
      }
    });
  });

  test('hostile bodies never throw', () {
    for (final body in <Object?>[
      <String, Object?>{'a': 1},
      5,
      ['x'],
      true,
      null,
      '',
      '   ',
    ]) {
      expect(
        IndexPolicy.fromEvent(
          searchEvent(encrypted, id, body: body),
          ownUserId: me,
        ),
        isNull,
        reason: '$body',
      );
    }
  });

  test('a huge body is cut and still indexed', () {
    final entry = IndexPolicy.fromEvent(
      searchEvent(encrypted, id, body: 'a' * 1000000),
      ownUserId: me,
    )!;
    expect(entry.text.length, IndexPolicy.maxTextChars);
  });

  test('the cut never splits an emoji', () {
    final entry = IndexPolicy.fromEvent(
      searchEvent(encrypted, id, body: '😀' * 2000),
      ownUserId: me,
    )!;
    expect(entry.text.runes.length, IndexPolicy.maxTextChars);
    expect(entry.text.runes.every((r) => r == 0x1F600), isTrue);
  });

  test('control and bidi characters are removed', () {
    final entry = IndexPolicy.fromEvent(
      searchEvent(encrypted, id, body: 'a\u202Eb\u0000c\u200Bd'),
      ownUserId: me,
    )!;
    expect(entry.text.contains('\u202E'), isFalse);
    expect(entry.text.contains('\u0000'), isFalse);
    expect(entry.text.contains('\u200B'), isFalse);
  });

  test('malformed ids and time stamps are not indexed', () {
    final now = DateTime(2031);
    expect(
      IndexPolicy.fromEvent(searchEvent(encrypted, 'no-dollar'), ownUserId: me),
      isNull,
    );
    expect(
      IndexPolicy.fromEvent(
        searchEvent(encrypted, id, senderId: 'alice'),
        ownUserId: me,
      ),
      isNull,
    );
    expect(
      IndexPolicy.fromEvent(
        searchEvent(encrypted, id, at: DateTime.fromMillisecondsSinceEpoch(0)),
        ownUserId: me,
      ),
      isNull,
    );
    expect(
      IndexPolicy.fromEvent(
        searchEvent(encrypted, id, at: DateTime(2040)),
        ownUserId: me,
        now: now,
      ),
      isNull,
    );
  });
}
