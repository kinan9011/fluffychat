// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io' show Platform;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show BuildContext, MediaQuery;

/// How much of the glass look the user wants: `auto` follows the device,
/// `full` always blurs, `lite` never does.
enum GlassMode {
  auto,
  full,
  lite;

  static GlassMode parse(Object? value) =>
      (value is String ? GlassMode.values.asNameMap()[value] : null) ??
      GlassMode.auto;
}

/// Whether a glass surface is drawn as a solid surface instead of a blur.
/// Reduce transparency and high contrast always win, then the user's choice,
/// then the device class.
bool glassIsSolid({
  required bool reduceTransparency,
  required bool highContrast,
  required GlassMode mode,
  required bool lowEnd,
  bool solidRequested = false,
}) =>
    solidRequested ||
    reduceTransparency ||
    highContrast ||
    mode == GlassMode.lite ||
    (mode == GlassMode.auto && lowEnd);

/// A blur costs fill rate on every frame. Telegram measures CPU and memory;
/// without a plugin the best signals are the number of cores on a native
/// device and "a phone browser" on the web.
bool detectLowEnd({
  required bool isWeb,
  required TargetPlatform platform,
  required int processors,
}) {
  if (isWeb) {
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }
  return processors <= 4;
}

/// The device class of this run, measured once at start. Tests set it.
abstract class DeviceClass {
  static bool lowEnd = detectLowEnd(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    processors: kIsWeb ? 8 : Platform.numberOfProcessors,
  );
}

/// The glass decision for the current settings and device.
bool glassIsSolidNow(BuildContext context, {bool solidRequested = false}) =>
    glassIsSolid(
      reduceTransparency: AppSettings.reduceTransparency.value,
      highContrast: MediaQuery.highContrastOf(context),
      mode: GlassMode.parse(AppSettings.glassMode.value),
      lowEnd: DeviceClass.lowEnd,
      solidRequested: solidRequested,
    );
