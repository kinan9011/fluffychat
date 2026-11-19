// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/rich_text/editor_text.dart';
import 'package:odango/utils/rich_text/format_state.dart';
import 'package:odango/utils/rich_text/html_parser.dart';

/// What the composer holds when the user edits a message: the formatted
/// version when `formatted_body` opens without loss, else the plain text.
class EditPrefill {
  const EditPrefill(this.text, this.format);

  final String text;
  final FormatState? format;

  static EditPrefill of(Event event, MatrixLocals locals) {
    final fallback = event.calcLocalizedBodyFallback(
      locals,
      withSenderNamePrefix: false,
      hideReply: true,
    );
    final html = event.content['formatted_body'];
    if (event.messageType != MessageTypes.Text ||
        event.content['format'] != 'org.matrix.custom.html' ||
        html is! String) {
      return EditPrefill(fallback, null);
    }
    final parsed = RichHtmlParser.parse(html);
    if (parsed == null ||
        parsed.lossy ||
        parsed.document.isPlain ||
        !RichEditorText.roundTrips(parsed.document)) {
      return EditPrefill(fallback, null);
    }
    final editor = RichEditorText.render(parsed.document);
    return EditPrefill(
      editor.text,
      FormatState(ranges: editor.ranges, richIntent: true),
    );
  }
}
