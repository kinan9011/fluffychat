// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/export/export_model.dart';

/// The name of an exported file. It is made from the event's position and a
/// cleaned copy of the sender's file name: no path separator, no `..`, no
/// leading dot, ASCII only, at most 80 characters after the index.
String safeMediaName(int index, String raw) {
  var name = raw
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
      .replaceAll(RegExp(r'\.{2,}'), '.')
      .replaceAll(RegExp(r'^[.\s_-]+'), '')
      .trim();
  if (name.length > 80) name = name.substring(name.length - 80);
  if (name.isEmpty) name = 'file';
  return '${index.toString().padLeft(6, '0')}-$name';
}

/// Spends the media allowance of one export on the bytes really read.
class MediaBudget {
  int _total = 0;

  int get used => _total;

  /// Whether a file of [size] bytes fits. Spends the allowance when it does.
  bool take(int size) {
    if (size < 0 || size > ExportLimits.maxMediaPerFile) return false;
    if (_total + size > ExportLimits.maxMediaTotal) return false;
    _total += size;
    return true;
  }

  bool couldFit(int claimedSize) =>
      claimedSize >= 0 &&
      claimedSize <= ExportLimits.maxMediaPerFile &&
      _total + claimedSize <= ExportLimits.maxMediaTotal;
}
