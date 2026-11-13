// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

const htmlImageDefaultDimension = 64.0;

/// Same as the largest image the timeline renders (see message_content.dart).
const htmlImageMaxDimension = 256.0;

const htmlImageMinDimension = 1.0;

typedef HtmlImageSize = ({double width, double height, bool isThumbnail});

HtmlImageSize htmlImageSize(String? widthAttr, String? heightAttr) {
  final width = _parseDimension(widthAttr);
  final height = _parseDimension(heightAttr);
  final declaredWidth = width ?? height ?? htmlImageDefaultDimension;
  final declaredHeight = height ?? width ?? htmlImageDefaultDimension;

  final scale = min(
    1.0,
    htmlImageMaxDimension / max(declaredWidth, declaredHeight),
  );
  return (
    width: (declaredWidth * scale).clamp(
      htmlImageMinDimension,
      htmlImageMaxDimension,
    ),
    height: (declaredHeight * scale).clamp(
      htmlImageMinDimension,
      htmlImageMaxDimension,
    ),
    isThumbnail:
        declaredWidth * declaredHeight >
        htmlImageMaxDimension * htmlImageMaxDimension,
  );
}

double? _parseDimension(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
  return parsed;
}
