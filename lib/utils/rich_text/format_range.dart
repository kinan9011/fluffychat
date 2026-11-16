// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// The order is persisted by index in drafts: only append.
enum RangeKind { bold, italic, underline, strike, code, spoiler, link, maths }

@immutable
class FormatRange {
  const FormatRange(this.start, this.end, this.kind, {this.link});

  final int start;
  final int end;
  final RangeKind kind;
  final Uri? link;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is FormatRange &&
      other.start == start &&
      other.end == end &&
      other.kind == kind &&
      other.link == link;

  @override
  int get hashCode => Object.hash(start, end, kind, link);

  @override
  String toString() => 'FormatRange($start, $end, ${kind.name})';
}
