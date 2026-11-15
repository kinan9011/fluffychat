// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show StringCharacters;

final _unsafe = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u061C\u180E\u200B\u200E\u200F\u2028-\u202E'
  r'\u2060-\u206F\uFEFF\u{E0000}-\u{E007F}]',
  unicode: true,
);

final _whitespace = RegExp(r'\s+');

final _markRun = RegExp(r'(\p{M}{3})\p{M}+', unicode: true);

const _firstStrongIsolate = '\u2068';
const _popDirectionalIsolate = '\u2069';

/// Display names, file names and similar strings come from other people. This
/// keeps what the eye reads equal to what is stored: control, line break,
/// bidi override/isolate and zero width characters are dropped, whitespace is
/// collapsed to single spaces, runs of combining marks are cut to three (a
/// stack of them paints far outside its line), and the result is cut to
/// [maxGraphemes].
String safeDisplayText(String input, {int maxGraphemes = 64}) {
  final cleaned = input
      .replaceAll(_unsafe, ' ')
      .replaceAll(_whitespace, ' ')
      .replaceAllMapped(_markRun, (match) => match.group(1)!)
      .trim();
  final characters = cleaned.characters;
  if (characters.length <= maxGraphemes) return cleaned;
  return '${characters.take(maxGraphemes - 1)}…';
}

/// [safeDisplayText] wrapped in a first strong isolate, so the text cannot
/// reorder the characters around it.
String isolatedDisplayText(String input, {int maxGraphemes = 64}) =>
    '$_firstStrongIsolate${safeDisplayText(input, maxGraphemes: maxGraphemes)}'
    '$_popDirectionalIsolate';
