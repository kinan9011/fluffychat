// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/rich_text/edit_prefill.dart';
import 'package:odango/utils/rich_text/format_range.dart';

import 'utils/test_client.dart';

void main() {
  late Room room;
  late MatrixLocals locals;

  setUpAll(() async {
    final client = await prepareTestClient();
    room = Room(id: '!room:example.org', client: client);
    locals = MatrixLocals(await L10n.delegate.load(const Locale('en')));
  });

  Event event(Map<String, Object?> content) => Event(
    type: EventTypes.Message,
    content: content,
    room: room,
    eventId: r'$e:example.org',
    senderId: '@bob:example.org',
    originServerTs: DateTime.now(),
  );

  test('a clean rich message opens formatted', () {
    final prefill = EditPrefill.of(
      event({
        'msgtype': 'm.text',
        'body': '**hi** there',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<strong>hi</strong> there',
      }),
      locals,
    );
    expect(prefill.text, 'hi there');
    expect(prefill.format?.ranges, [const FormatRange(0, 2, RangeKind.bold)]);
    expect(prefill.format?.richIntent, isTrue);
  });

  test('a message with a mention pill opens as plain text, not rich', () {
    final prefill = EditPrefill.of(
      event({
        'msgtype': 'm.text',
        'body': 'hi @Alice there',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            'hi <a href="https://matrix.to/#/@alice:example.org">Alice</a> '
            'there',
      }),
      locals,
    );
    expect(prefill.text, 'hi @Alice there');
    expect(prefill.format, isNull);
  });

  test('a list opens with its prefixes', () {
    final prefill = EditPrefill.of(
      event({
        'msgtype': 'm.text',
        'body': '- a\n- b',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>a</li><li>b</li></ul>',
      }),
      locals,
    );
    expect(prefill.text, '- a\n- b');
  });

  test('images and colours are lossy: the plain body opens', () {
    for (final html in [
      'x <img data-mx-emoticon src="mxc://a/b" alt=":x:">',
      '<font color="red">x</font>',
      '<table><tr><td>x</td></tr></table>',
      '<strong>x</strong> <img data-mx-emoticon src="mxc://a/b" alt=":x:">',
      '<strong>x</strong> <font color="red">y</font>',
      '<strong>x</strong><ul><li>a<ul><li>b</li></ul></li></ul>',
    ]) {
      final prefill = EditPrefill.of(
        event({
          'msgtype': 'm.text',
          'body': 'x :x:',
          'format': 'org.matrix.custom.html',
          'formatted_body': html,
        }),
        locals,
      );
      expect(prefill.text, 'x :x:');
      expect(prefill.format, isNull);
    }
  });

  test('html without formatting opens as the plain body', () {
    final prefill = EditPrefill.of(
      event({
        'msgtype': 'm.text',
        'body': 'plain',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<p>plain</p>',
      }),
      locals,
    );
    expect(prefill.text, 'plain');
    expect(prefill.format, isNull);
  });

  test('a paragraph that looks like a prefix keeps the plain body', () {
    final prefill = EditPrefill.of(
      event({
        'msgtype': 'm.text',
        'body': 'the body text',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<strong>a</strong><br>- x',
      }),
      locals,
    );
    expect(prefill.text, 'the body text');
    expect(prefill.format, isNull);
  });

  test('an emote or a message without format opens as the plain body', () {
    expect(
      EditPrefill.of(
        event({
          'msgtype': 'm.emote',
          'body': 'waves',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<strong>waves</strong>',
        }),
        locals,
      ).format,
      isNull,
    );
    expect(
      EditPrefill.of(event({'msgtype': 'm.text', 'body': 'x'}), locals).format,
      isNull,
    );
  });

  test('a reply fallback is not part of the edit text', () {
    final prefill = EditPrefill.of(
      event({
        'msgtype': 'm.text',
        'body': '> <@a:example.org> old\n\nnew',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            '<mx-reply><blockquote>old</blockquote></mx-reply><strong>new</strong>',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$old:example.org'},
        },
      }),
      locals,
    );
    expect(prefill.text, 'new');
  });
}
