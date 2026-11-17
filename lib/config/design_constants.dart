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

/// Settings cards and rows (DESIGN.md 7.14).
abstract class AppSettingsLayout {
  static const double cardRadius = 20;
  static const double rowHeight = 50;
  static const double rowHeightSub = 62;
  static const double tile = 32;
  static const double tileRadius = 10;
  static const double dividerInset = 58;
  static const double rowPadding = 14;
  static const double switchWidth = 46;
  static const double switchHeight = 28;
  static const double knob = 22;
  static const double sideMargin = 14;
  static const double maxWidth = 600;
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
  static const double formatCell = 38;
  static const double formatCellRadius = 12;
  static const double formatPanelRadius = 22;
  static const double formatPanelPadding = 10;
  static const double formatGap = 6;
  static const double formatPanelMinHeight = 80;
  static const double formatPanelMaxHeight = 220;
  static const double formatPanelReserve = 160;
  static const double quickBarHeight = 46;
  static const double quickBarButton = 36;
  static const double quickBarRadius = 23;
  static const double quickBarButtonRadius = 12;
  static const double attachBarHeight = 66;
  static const double attachItemWidth = 72;
  static const double attachBarRadius = 33;
  static const double attachItemRadius = 28;
  static const double historyBubbleRadius = 18;
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

/// Send options, schedule sheet and scheduled list (DESIGN.md 7.12, 7.13,
/// 9.8, mockup screens 03-05).
abstract class AppSchedule {
  static const double menuWidth = 272;
  static const double menuRow = 50;
  static const double menuGap = 10;
  static const double sheetHandleWidth = 40;
  static const double sheetHandleHeight = 4;
  static const double closeButton = 34;
  static const double presetRadius = 16;
  static const double presetGap = 8;
  static const double wheelRadius = 18;
  static const double wheelRow = 38;
  static const int wheelRows = 5;
  static const double wheelHighlightHeight = 40;
  static const double wheelHighlightRadius = 12;
  static const double primaryButton = 54;
  static const double chipRadius = 16;
  static const double groupChipRadius = 12;
  static const double badge = 16;
  static const double badgeIcon = 11;
  static const double actionIcon = 17;
  static const double bubbleMaxFraction = 0.82;
  static const double overlayBlur = 4;
  static const double sheetMaxHeight = 720;
}

abstract class AppTopics {
  static const double rowHeight = 72;
  static const double iconTile = 48;
  static const double iconTileRadius = 15;
  static const double iconSize = 24;
  static const double badge = 22;
  static const double fabHeight = 54;
  static const double chipHeight = 32;
  static const double chipTap = 44;
  static const double chipBarHeight = 44;
  static const double segmentHeight = 34;
  static const int maxChips = 8;
}

abstract class AppTypography {
  static const monoFamily = 'JetBrainsMono';
  static const mono = TextStyle(fontFamily: monoFamily);

  /// Keeps Matrix IDs and server names left-to-right inside RTL text.
  static String ltr(String text) => '\u2066$text\u2069';
}

/// Bounds for composing, parsing and rendering formatted messages.
abstract class RichLimits {
  static const int maxBlocks = 500;
  static const int maxLinks = 100;
  static const int maxMaths = 50;
  static const int maxMathsUnits = 2048;
  static const int maxTextUnits = 16000;
  static const int maxBodyBytes = 24000;
  static const int maxHtmlBytes = 24000;
  static const int maxEventBytes = 60000;
  static const int eventOverheadBytes = 1024;
  static const int encryptionOverheadBytes = 512;
  static const int maxLinkUnits = 2048;
  static const int maxRanges = 500;
  static const int maxUndo = 100;
  static const int maxEdits = 50;
  static const int maxEditUnits = 16000;
  static const int maxDiffTokens = 400;
  static const int maxParseNodes = 2000;
  static const int maxParseDepth = 20;
  static const int maxParseInputUnits = 65536;
  static const int maxRenderElements = 3000;
  static const int maxRenderDepth = 40;
  static const int maxRenderHeadings = 100;
  static const int maxRenderSpoilers = 100;
  static const int maxRenderMaths = 50;
  static const int maxRenderMathsUnits = 4096;
}
