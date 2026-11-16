// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/utils/rich_text/rich_document.dart';

const _alphabet = [
  'a',
  'b',
  'Z',
  ' ',
  ' ',
  '<',
  '>',
  '&',
  '"',
  "'",
  '1',
  '😀',
  'ع',
  '.',
  '/',
  '=',
];

const _links = [
  'https://example.org/',
  'https://example.org/a?b=1&c=2',
  'mailto:a@b.org',
  'matrix:r/room:server.org',
];

String _text(Random random, {int max = 12}) => List.generate(
  1 + random.nextInt(max),
  (_) => _alphabet[random.nextInt(_alphabet.length)],
).join();

String _tex(Random random) {
  final value = _text(random, max: 8).trim();
  return value.isEmpty ? 'x' : value;
}

List<Inline> _inlines(Random random) => [
  for (var i = 0; i < 1 + random.nextInt(4); i++)
    if (random.nextInt(8) == 0)
      MathsInline(_tex(random))
    else
      TextRun(
        _text(random),
        marks: {
          for (final mark in InlineMark.values)
            if (random.nextInt(5) == 0) mark,
        },
        link: random.nextInt(6) == 0
            ? Uri.parse(_links[random.nextInt(_links.length)])
            : null,
      ),
];

/// Documents the serializer can produce, from a fixed seed.
RichDocument randomDocument(Random random, {bool safeStart = false}) {
  final doc = _randomDocument(random);
  if (!safeStart) return doc;
  return RichDocument([
    for (final block in doc.blocks)
      block.isVerbatim
          ? block
          : Block(
              block.kind,
              [const TextRun('x'), ...block.inlines],
              level: block.level,
              checked: block.checked,
            ),
  ]);
}

RichDocument _randomDocument(Random random) => RichDocument([
  for (var i = 0; i < 1 + random.nextInt(8); i++)
    switch (BlockKind.values[random.nextInt(BlockKind.values.length)]) {
      BlockKind.paragraph => Block(BlockKind.paragraph, _inlines(random)),
      BlockKind.heading => Block(
        BlockKind.heading,
        _inlines(random),
        level: 1 + random.nextInt(6),
      ),
      BlockKind.quote => Block(BlockKind.quote, _inlines(random)),
      BlockKind.bullet => Block(BlockKind.bullet, _inlines(random)),
      BlockKind.ordered => Block(BlockKind.ordered, _inlines(random)),
      BlockKind.checklist => Block(
        BlockKind.checklist,
        _inlines(random),
        checked: random.nextBool(),
      ),
      BlockKind.codeBlock => Block(BlockKind.codeBlock, [
        TextRun(_text(random, max: 30).replaceAll(' ', '\n')),
      ], language: random.nextBool() ? 'dart' : null),
      BlockKind.mathsBlock => Block(BlockKind.mathsBlock, [
        TextRun(_tex(random)),
      ]),
    },
]);
