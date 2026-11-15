// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class MenuPlacement {
  final Offset barTopLeft;
  final Offset menuTopLeft;
  final bool menuAbove;

  const MenuPlacement({
    required this.barTopLeft,
    required this.menuTopLeft,
    required this.menuAbove,
  });
}

/// The height of a menu with [rows] one-line rows. Rows grow with the text
/// scale, so the estimate follows it; wrapped labels are what the scroll
/// bound of the card is for.
double menuHeightFor(int rows, TextScaler textScaler) =>
    rows * math.max(46.0, textScaler.scale(15.5) * 1.25) + 12;

/// Where the reaction bar and the context menu go around a pressed bubble
/// ([anchor], global coordinates). The bar goes above the bubble, the menu
/// below it; each flips when it does not fit, and when nothing fits around the
/// bubble they stack at the top of the safe area. Both are clamped into the
/// safe area, edges follow the side the bubble is on.
MenuPlacement placeMessageMenu({
  required Rect anchor,
  required Size screen,
  required EdgeInsets safe,
  required Size barSize,
  required Size menuSize,
  required bool outgoing,
  required TextDirection direction,
  double gap = 8,
}) {
  final minX = safe.left + gap;
  final maxX = math.max(minX, screen.width - safe.right - gap);
  final minY = safe.top + gap;
  final maxY = math.max(minY, screen.height - safe.bottom - gap);

  final endsAtRight = outgoing == (direction == TextDirection.ltr);
  double x(Size size) => (endsAtRight ? anchor.right - size.width : anchor.left)
      .clamp(minX, math.max(minX, maxX - size.width))
      .toDouble();
  double clampY(double y, Size size) =>
      y.clamp(minY, math.max(minY, maxY - size.height)).toDouble();

  final barH = barSize.height > 0 ? barSize.height + gap : 0.0;
  final fitsAbove = anchor.top - minY >= barH;
  final menuFitsBelow =
      maxY - anchor.bottom >= menuSize.height + (fitsAbove ? 0 : barH) + gap;
  final menuFitsAbove = anchor.top - minY >= menuSize.height + barH + gap;

  final barGap = barSize.height > 0 ? gap : 0.0;
  final (barY, menuY, menuAbove) = switch ((
    fitsAbove,
    menuFitsBelow,
    menuFitsAbove,
  )) {
    (true, true, _) => (
      anchor.top - gap - barSize.height,
      anchor.bottom + gap,
      false,
    ),
    (_, _, true) => (
      anchor.top - gap - menuSize.height - gap - barSize.height,
      anchor.top - gap - menuSize.height,
      true,
    ),
    (false, true, _) => (
      anchor.bottom + gap,
      anchor.bottom + gap + barSize.height + barGap,
      false,
    ),
    _ => (minY, minY + barSize.height + barGap, false),
  };
  return MenuPlacement(
    barTopLeft: Offset(x(barSize), clampY(barY, barSize)),
    menuTopLeft: Offset(x(menuSize), clampY(menuY, menuSize)),
    menuAbove: menuAbove,
  );
}
