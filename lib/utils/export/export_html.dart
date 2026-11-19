// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/utils/export/export_model.dart';

final _controls = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u061C\u200E\u200F'
  r'\u202A-\u202E\u2066-\u2069\uFEFF]',
);

/// The only way text gets into the HTML export. Everything that is not the
/// fixed template (names, topics, message text, file names, ids) passes
/// through here: control and bidi override characters are dropped and the
/// five characters that can open a tag or leave an attribute are escaped.
String esc(String input) {
  final cleaned = input.replaceAll(_controls, '');
  final out = StringBuffer();
  for (final unit in cleaned.runes) {
    switch (unit) {
      case 0x26:
        out.write('&amp;');
      case 0x3C:
        out.write('&lt;');
      case 0x3E:
        out.write('&gt;');
      case 0x22:
        out.write('&quot;');
      case 0x27:
        out.write('&#39;');
      case 0x60:
        out.write('&#96;');
      default:
        out.writeCharCode(unit);
    }
  }
  return out.toString();
}

String _clip(String text) => text.length <= ExportLimits.maxTextPerMessage
    ? text
    : '${text.substring(0, ExportLimits.maxTextPerMessage)}…';

String _two(int n) => n.toString().padLeft(2, '0');

String formatExportTime(DateTime time) {
  final t = time.toUtc();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)} UTC';
}

const _style = '''
body{font:15px/1.45 system-ui,sans-serif;max-width:760px;margin:24px auto;padding:0 16px;color:#1b1b1f;background:#fff}
h1{font-size:22px;margin:0 0 4px}
.meta{color:#666;font-size:13px;margin:0 0 20px}
.msg{padding:8px 12px;margin:6px 0;border-radius:14px;background:#f1f1f5}
.who{font-weight:600;font-size:13px}
.time{color:#666;font-weight:400;margin-inline-start:8px}
.text{white-space:normal;overflow-wrap:anywhere}
.note{color:#666;font-size:13px;font-style:italic}
a{color:#3b4fd8}
@media (prefers-color-scheme:dark){body{color:#ececf1;background:#111114}.msg{background:#1c1c22}.meta,.time,.note{color:#9a9aa5}a{color:#9aa7ff}}
''';

/// A readable copy of the chat. Plain text only: the HTML of a message
/// (`formatted_body`) is never exported, links in text are not made clickable,
/// and the page forbids scripts, styles from outside and images by its CSP.
/// Media is only linked, from names this app generated ([mediaPaths], by the
/// position of the event in [events]). The build stops with [ExportTooLarge] as
/// soon as the page is longer than [maxLength].
String buildHtml(
  ExportMeta meta,
  List<ExportEvent> events, {
  Map<int, String> mediaPaths = const {},
  String truncatedNote = '',
  String mediaSkippedNote = '',
  int maxLength = ExportLimits.maxTextOutputBytes,
}) {
  final out = StringBuffer()
    ..write('<!doctype html>\n<html dir="auto"><head><meta charset="utf-8">')
    ..write(
      '<meta http-equiv="Content-Security-Policy" '
      'content="default-src \'none\'; style-src \'unsafe-inline\'; img-src \'none\'">',
    )
    ..write(
      '<meta name="viewport" content="width=device-width,initial-scale=1">',
    )
    ..write(
      '<title>${esc(meta.roomName)}</title><style>$_style</style></head><body>',
    )
    ..write('<h1 dir="auto">${esc(meta.roomName)}</h1>')
    ..write('<p class="meta" dir="auto">');
  final topic = meta.topic;
  if (topic != null && topic.isNotEmpty) out.write('${esc(topic)} · ');
  out.write('${esc(formatExportTime(meta.exportedAt))}</p>');
  if (meta.truncated && truncatedNote.isNotEmpty) {
    out.write('<p class="note">${esc(truncatedNote)}</p>');
  }
  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    out
      ..write('<div class="msg"><div class="who" dir="auto">')
      ..write(esc(event.senderName))
      ..write('<span class="time">${esc(formatExportTime(event.time))}</span>')
      ..write('</div>');
    final text = esc(_clip(event.text)).replaceAll('\n', '<br>');
    if (text.isNotEmpty) out.write('<div class="text" dir="auto">$text</div>');
    final path = mediaPaths[i];
    final name = event.mediaName;
    if (path != null && name != null) {
      out.write(
        '<div class="text"><a href="${esc(path)}">${esc(name)}</a></div>',
      );
    }
    out.write('</div>');
    if (out.length > maxLength) throw const ExportTooLarge();
  }
  if (mediaSkippedNote.isNotEmpty) {
    out.write('<p class="note">${esc(mediaSkippedNote)}</p>');
  }
  out.write('</body></html>\n');
  return out.toString();
}
