// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/appearance/chat_appearance.dart';
import 'package:material_ui/material_ui.dart';

/// 20 px on every corner, the sender-side bottom corner of the last bubble of
/// a run is the 6 px tail (DESIGN.md 7.5). Directional so RTL mirrors.
BorderRadiusDirectional bubbleRadius({
  required bool outgoing,
  required bool tail,
  BubbleCorners corners = BubbleCorners.standard,
}) {
  final round = Radius.circular(corners.radius);
  final tailCorner = Radius.circular(corners.tail);
  return BorderRadiusDirectional.only(
    topStart: round,
    topEnd: round,
    bottomStart: tail && !outgoing ? tailCorner : round,
    bottomEnd: tail && outgoing ? tailCorner : round,
  );
}

double bubbleMaxWidth(double available) => math.min(
  available * AppChat.bubbleMaxFraction,
  FluffyThemes.columnWidth * 1.5,
);
