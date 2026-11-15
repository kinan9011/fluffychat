// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Shape (DESIGN.md 6.4). Pills use half of the element height.
abstract class AppRadius {
  static const double sheet = 28;
  static const double card = 20;
  static const double bubble = 20;
  static const double bubbleTail = 6;
  static const double menu = 22;
  static const double composer = 26;
  static const double reactionBar = 26;
  static const double banner = 18;
  static const double iconTile = 10;
  static const double spaceAvatarFactor = 0.3;
}

/// Spacing scale (DESIGN.md 6.4).
abstract class AppSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double s = 8;
  static const double m = 10;
  static const double l = 12;
  static const double xl = 14;
  static const double xxl = 16;
  static const double xxxl = 18;
  static const double huge = 24;
  static const double giant = 32;
}

/// Elevation levels 1-4 (DESIGN.md 6.5); level 0 is no shadow. [shadow] is
/// `AppTokens.shadow`; menus use their own stronger black.
abstract class AppElevation {
  static List<BoxShadow> bubble(Color shadow) => [
    BoxShadow(color: shadow, offset: const Offset(0, 1), blurRadius: 2),
  ];

  static List<BoxShadow> glass(Color shadow) => [
    BoxShadow(color: shadow, offset: const Offset(0, 5), blurRadius: 16),
  ];

  static List<BoxShadow> bottomBar(Color shadow) => [
    BoxShadow(color: shadow, offset: const Offset(0, 8), blurRadius: 28),
  ];

  static const List<BoxShadow> reactionBar = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.2),
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  static const List<BoxShadow> menu = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.235),
      offset: Offset(0, 16),
      blurRadius: 40,
    ),
  ];
}

/// Conversation layout constants (DESIGN.md 5.2, 7.5-7.12).
abstract class AppChat {
  static const double headerButton = 48;
  static const double headerGap = 8;
  static const double headerTopGap = 4;
  static const double headerAvatar = 38;
  static const double composerHeight = 52;
  static const double actionButton = 52;
  static const double jumpButton = 46;
  static const double jumpHit = 48;
  static const double jumpBadge = 20;
  static const double bubbleAvatar = 30;
  static const double mapBubbleWidth = 280;
  static const double menuGap = 8;
  static const double groupGap = 6;
  static const double wallpaperGrid = 18;
  static const double wallpaperDotRadius = 1.4;
  static const double menuWidth = 246;
  static const double reactionBarEmoji = 38;
  static const double bubbleMaxFraction = 0.82;
  static const int waveformBars = 26;
  static const int maxReactionKeys = 24;
  static const int maxMentionScan = 500;
  static const int maxWallpaperDots = 40000;

  static double listTopPadding({
    required double topInset,
    required int bannerCount,
    required double bannerHeight,
    double extraHeight = 0,
  }) =>
      topInset +
      headerTopGap +
      headerButton +
      headerGap +
      bannerCount * bannerHeight +
      extraHeight;

  static const double newDeviceBannerHeight = 56;
}

abstract class AppTypography {
  static const monoFamily = 'JetBrainsMono';
  static const mono = TextStyle(fontFamily: monoFamily);

  /// Keeps Matrix IDs and server names left-to-right inside RTL text.
  static String ltr(String text) => '\u2066$text\u2069';
}
