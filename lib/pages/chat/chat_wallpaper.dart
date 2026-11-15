// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Gradient plus dot grid (DESIGN.md 6.1 `--wallG`, `--dot2`). A wallpaper the
/// user picked is drawn over the gradient without the dots.
class ChatWallpaper extends StatelessWidget {
  @visibleForTesting
  static const dotsKey = ValueKey('chat_wallpaper_dots');

  final ApplicationAccountConfig config;
  final Client? client;

  const ChatWallpaper({required this.config, this.client, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final url = config.wallpaperUrl;
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: tokens.wallG)),
        if (url == null)
          RepaintBoundary(
            key: dotsKey,
            child: CustomPaint(painter: WallpaperDots(tokens.dot2)),
          )
        else
          Opacity(
            opacity: config.wallpaperOpacity ?? 0.5,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: config.wallpaperBlur ?? 0.0,
                sigmaY: config.wallpaperBlur ?? 0.0,
              ),
              child: MxcImage(
                client: client,
                cacheKey: url.toString(),
                uri: url,
                fit: BoxFit.cover,
                height: size.height,
                width: size.width,
                isThumbnail: false,
                placeholder: (_) => Container(),
              ),
            ),
          ),
      ],
    );
  }
}

class WallpaperDots extends CustomPainter {
  final Color color;

  const WallpaperDots(this.color);

  @visibleForTesting
  static List<Offset> dotCenters(Size size) {
    if (!size.width.isFinite || !size.height.isFinite) return [];
    const grid = AppChat.wallpaperGrid;
    final columns = (size.width / grid).floor();
    if (columns <= 0) return [];
    final rows = math.min(
      (size.height / grid).floor(),
      AppChat.maxWallpaperDots ~/ columns + 1,
    );
    final dots = <Offset>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if (dots.length >= AppChat.maxWallpaperDots) return dots;
        dots.add(Offset(grid / 2 + column * grid, grid / 2 + row * grid));
      }
    }
    return dots;
  }

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPoints(
    ui.PointMode.points,
    dotCenters(size),
    Paint()
      ..color = color
      ..strokeWidth = AppChat.wallpaperDotRadius * 2
      ..strokeCap = StrokeCap.round,
  );

  @override
  bool shouldRepaint(WallpaperDots oldDelegate) => oldDelegate.color != color;
}
