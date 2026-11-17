// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension ApplicationAccountConfigExtension on Client {
  static const String accountDataKey = 'im.fluffychat.account_config';

  ApplicationAccountConfig get applicationAccountConfig =>
      ApplicationAccountConfig.fromJson(
        accountData[accountDataKey]?.content ?? {},
      );

  Future<void> setApplicationAccountConfig(ApplicationAccountConfig config) =>
      setAccountData(userID!, accountDataKey, config.toJson());

  /// Only updates the specified values in ApplicationAccountConfig
  Future<void> updateApplicationAccountConfig(ApplicationAccountConfig config) {
    final currentConfig = applicationAccountConfig;
    return setAccountData(
      userID!,
      accountDataKey,
      ApplicationAccountConfig(
        wallpaperUrl: config.wallpaperUrl ?? currentConfig.wallpaperUrl,
        wallpaperOpacity:
            config.wallpaperOpacity ?? currentConfig.wallpaperOpacity,
        wallpaperBlur: config.wallpaperBlur ?? currentConfig.wallpaperBlur,
      ).toJson(),
    );
  }
}

class ApplicationAccountConfig {
  final Uri? wallpaperUrl;
  final double? wallpaperOpacity;
  final double? wallpaperBlur;

  const ApplicationAccountConfig({
    this.wallpaperUrl,
    this.wallpaperOpacity,
    this.wallpaperBlur,
  });

  static double _sanitizedOpacity(double? opacity) {
    if (opacity == null) return 1;
    if (opacity > 1 || opacity < 0) return 1;
    return opacity;
  }

  static Uri? _mxcOnly(Object? value) {
    if (value is! String || value.length > 2048) return null;
    final uri = Uri.tryParse(value);
    return uri != null && uri.isScheme('mxc') ? uri : null;
  }

  static double? _sanitizedBlur(double? blur) {
    if (blur == null || !blur.isFinite) return null;
    return blur.clamp(0, 50).toDouble();
  }

  factory ApplicationAccountConfig.fromJson(Map<String, dynamic> json) =>
      ApplicationAccountConfig(
        wallpaperUrl: _mxcOnly(json['wallpaper_url']),
        wallpaperOpacity: _sanitizedOpacity(
          json.tryGet<double>('wallpaper_opacity'),
        ),
        wallpaperBlur: _sanitizedBlur(json.tryGet<double>('wallpaper_blur')),
      );

  Map<String, dynamic> toJson() => {
    'wallpaper_url': wallpaperUrl?.toString(),
    'wallpaper_opacity': wallpaperOpacity,
    'wallpaper_blur': wallpaperBlur,
  };
}
