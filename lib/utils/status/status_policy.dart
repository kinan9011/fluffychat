// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/display_text.dart';

enum StatusClearAfter { hour, today, week, never }

/// When a status with this clear-after choice should be removed, in local
/// time. The server has no expiry for presence text, so the client does it.
DateTime? statusClearAt(StatusClearAfter after, DateTime now) {
  switch (after) {
    case StatusClearAfter.hour:
      return now.add(const Duration(hours: 1));
    case StatusClearAfter.today:
      return DateTime(now.year, now.month, now.day + 1);
    case StatusClearAfter.week:
      var days = (DateTime.monday - now.weekday + 7) % 7;
      if (days == 0) days = 7;
      return DateTime(now.year, now.month, now.day + days);
    case StatusClearAfter.never:
      return null;
  }
}

const maxStatusLength = 255;

/// The text to publish: one line, no control or bidi characters, at most
/// [maxStatusLength] characters. Null (clear the status) when nothing is left.
String? sanitizeStatus(String input) {
  final text = safeDisplayText(input, maxGraphemes: maxStatusLength);
  return text.isEmpty ? null : text;
}

/// Another person's status as it may be shown: the same cleaning as the text
/// a user can publish, null when nothing readable is left.
String? displayStatus(String? raw) => raw == null ? null : sanitizeStatus(raw);
