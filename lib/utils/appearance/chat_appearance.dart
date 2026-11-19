// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:odango/utils/oklch.dart';

/// Bubble corner radius presets (DESIGN.md 7.5 fixes 20 px as the default).
enum BubbleCorners {
  sharp(10),
  standard(20),
  round(26);

  const BubbleCorners(this.radius);

  final double radius;

  double get tail => math.min(6, radius);

  static BubbleCorners? byName(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// A wallpaper the user can pick. [colors] is null for the theme default.
class WallpaperPreset {
  const WallpaperPreset(this.id, this.colors);

  final String id;
  final List<Color>? colors;

  static final defaultPreset = WallpaperPreset('default', null);
}

final wallpaperPresets = <WallpaperPreset>[
  WallpaperPreset.defaultPreset,
  WallpaperPreset('meadow', [
    oklchColor(0.92, 0.05, 140),
    oklchColor(0.88, 0.06, 200),
  ]),
  WallpaperPreset('sunset', [
    oklchColor(0.93, 0.05, 60),
    oklchColor(0.88, 0.07, 20),
  ]),
  WallpaperPreset('night', [
    oklchColor(0.35, 0.05, 260),
    oklchColor(0.22, 0.05, 300),
  ]),
  WallpaperPreset('paper', [
    oklchColor(0.94, 0.005, 270),
    oklchColor(0.94, 0.005, 270),
  ]),
];

WallpaperPreset wallpaperPresetById(Object? id) {
  for (final preset in wallpaperPresets) {
    if (preset.id == id) return preset;
  }
  return WallpaperPreset.defaultPreset;
}

bool isWallpaperPresetId(Object? id) =>
    wallpaperPresets.any((preset) => preset.id == id);

/// Per-chat appearance in the room account data of the user. Everything in it
/// is untrusted: other clients or a hostile server can write it.
class RoomAppearance {
  const RoomAppearance({this.preset, this.accentHue, this.corners});

  static const type = 'com.swovo.odango.chat_appearance';
  static const maxBytes = 512;

  final String? preset;
  final int? accentHue;
  final BubbleCorners? corners;

  static RoomAppearance? tryParse(Object? content) {
    if (content is! Map) return null;
    if (content.keys.any((key) => key is! String)) return null;
    try {
      if (utf8.encode(jsonEncode(content)).length > maxBytes) return null;
    } catch (_) {
      return null;
    }
    if (content['v'] != 1) return null;
    final preset = content['preset'];
    final hue = content['accent_hue'];
    final corners = BubbleCorners.byName(content['corners']);
    final result = RoomAppearance(
      preset: isWallpaperPresetId(preset) ? preset as String : null,
      accentHue: hue is int && hue >= 0 && hue <= 359 ? hue : null,
      corners: corners,
    );
    return result.isEmpty ? null : result;
  }

  bool get isEmpty => preset == null && accentHue == null && corners == null;

  Map<String, Object?> toContent() => {
    'v': 1,
    'preset': ?preset,
    'accent_hue': ?accentHue,
    if (corners != null) 'corners': corners!.name,
  };

  RoomAppearance copyWith({
    String? preset,
    int? accentHue,
    BubbleCorners? corners,
  }) => RoomAppearance(
    preset: preset ?? this.preset,
    accentHue: accentHue ?? this.accentHue,
    corners: corners ?? this.corners,
  );
}

class GlobalAppearance {
  const GlobalAppearance({
    required this.preset,
    required this.accentHue,
    required this.corners,
  });

  final String preset;
  final double accentHue;
  final BubbleCorners corners;
}

class ResolvedAppearance {
  const ResolvedAppearance({
    required this.preset,
    required this.accentHue,
    required this.corners,
    required this.hasRoomOverride,
    required this.hasRoomPreset,
  });

  final String preset;
  final double accentHue;
  final BubbleCorners corners;
  final bool hasRoomOverride;

  /// The chat has its own wallpaper preset, which beats a picture chosen for
  /// all chats.
  final bool hasRoomPreset;
}

ResolvedAppearance resolveAppearance({
  required GlobalAppearance global,
  RoomAppearance? room,
}) => ResolvedAppearance(
  preset: room?.preset ?? global.preset,
  accentHue: room?.accentHue?.toDouble() ?? global.accentHue,
  corners: room?.corners ?? global.corners,
  hasRoomOverride: room != null,
  hasRoomPreset: room?.preset != null,
);
