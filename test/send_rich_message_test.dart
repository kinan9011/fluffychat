// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/format_state.dart';
import 'package:fluffychat/utils/rich_text/outgoing_message.dart';
import 'package:fluffychat/utils/rich_text/send_rich_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

RichOutgoing rich(String text, List<FormatRange> ranges) =>
    planOutgoing(text, FormatState(ranges: ranges)) as RichOutgoing;

Future<Map<String, Object?>> capture(
  Room room,
  Future<Object?> Function() send,
) async {
  FakeMatrixApi.calledEndpoints.clear();
  try {
    await send();
  } catch (_) {}
  final sends = FakeMatrixApi.calledEndpoints.entries
      .where((e) => e.key.contains('/send/m.room.message/'))
      .toList();
  expect(sends, hasLength(1));
  expect(sends.single.value, hasLength(1));
  final others = FakeMatrixApi.calledEndpoints.keys.where(
    (k) => !k.contains('/send/m.room.message/'),
  );
  expect(
    others.where(
      (k) =>
          k.contains('receipt') ||
          k.contains('typing') ||
          k.contains('presence') ||
          k.contains('relations') ||
          k.contains('read_markers'),
    ),
    isEmpty,
  );
  final body = sends.single.value.single;
  return Map<String, Object?>.from(
    body is String ? jsonDecode(body) as Map : body as Map,
  );
}

void main() {
  late Room room;

  setUp(() async {
    final client = await prepareTestClient();
    room = Room(id: '!localpart:server.abc', client: client);
  });

  test('one PUT with the escaped html and the masked body', () async {
    final message = rich('the SECRET <b>&', [
      const FormatRange(4, 10, RangeKind.spoiler),
      const FormatRange(11, 15, RangeKind.bold),
    ]);
    final content = await capture(room, () => sendRichMessage(room, message));
    expect(content['msgtype'], 'm.text');
    expect(content['format'], 'org.matrix.custom.html');
    expect(
      content['formatted_body'],
      'the <span data-mx-spoiler>SECRET</span> <strong>&lt;b&gt;&amp;</strong>',
    );
    expect(content['body'], 'the [spoiler] **<b>&**');
    expect(content['body'].toString(), isNot(contains('SECRET')));
  });

  test('hostile text arrives escaped', () async {
    final message = rich('<script>alert(1)</script>', [
      const FormatRange(0, 25, RangeKind.bold),
    ]);
    final content = await capture(room, () => sendRichMessage(room, message));
    expect(content['formatted_body'], isNot(contains('<script')));
    expect(content['formatted_body'], contains('&lt;script&gt;'));
  });

  test('mentions come from the plain text', () async {
    final message = rich('hey @alice:example.org', [
      const FormatRange(4, 22, RangeKind.bold),
    ]);
    final content = await capture(room, () => sendRichMessage(room, message));
    expect(content['m.mentions'], {
      'user_ids': ['@alice:example.org'],
    });
  });

  test('an edit carries m.new_content and the star prefix', () async {
    final message = rich('edited', [const FormatRange(0, 6, RangeKind.italic)]);
    final content = await capture(
      room,
      () => sendRichMessage(room, message, editEventId: r'$original'),
    );
    expect(content['m.new_content'], isA<Map>());
    expect(
      (content['m.new_content'] as Map)['formatted_body'],
      '<em>edited</em>',
    );
    expect(content['formatted_body'], '* <em>edited</em>');
    expect((content['m.relates_to'] as Map)['rel_type'], 'm.replace');
  });

  test('a thread reply is a thread relation', () async {
    final message = rich('in thread', [
      const FormatRange(0, 2, RangeKind.bold),
    ]);
    final content = await capture(
      room,
      () => sendRichMessage(room, message, threadRootEventId: r'$root'),
    );
    expect((content['m.relates_to'] as Map)['rel_type'], 'm.thread');
  });
}
