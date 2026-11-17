// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/appearance/chat_appearance.dart';
import 'package:fluffychat/utils/appearance/chat_appearance_scope.dart';
import 'package:fluffychat/utils/appearance/wallpaper_store.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Gradient plus dot grid (DESIGN.md 6.1 `--wallG`, `--dot2`). A picture the
/// user picked (local file, or the legacy account data one) is drawn over the
/// gradient without the dots. A preset replaces the theme gradient.
class ChatWallpaper extends StatefulWidget {
  @visibleForTesting
  static const dotsKey = ValueKey('chat_wallpaper_dots');
  @visibleForTesting
  static const localImageKey = ValueKey('chat_wallpaper_local_image');

  final ApplicationAccountConfig config;
  final Client? client;
  final ResolvedAppearance? appearance;
  final LocalWallpaperStore? store;

  const ChatWallpaper({
    required this.config,
    this.client,
    this.appearance,
    this.store,
    super.key,
  });

  @override
  State<ChatWallpaper> createState() => _ChatWallpaperState();
}

class _ChatWallpaperState extends State<ChatWallpaper> {
  Uint8List? _local;
  int _loads = 0;

  LocalWallpaperStore get _store => widget.store ?? LocalWallpaperStore();

  @override
  void initState() {
    super.initState();
    AppSettings.chatWallpaperLocal.listenable.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppSettings.chatWallpaperLocal.listenable.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final load = ++_loads;
    if (!AppSettings.chatWallpaperLocal.value) {
      if (_local != null && mounted) setState(() => _local = null);
      return;
    }
    Uint8List? bytes;
    try {
      bytes = await (await _store.current())?.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    if (!mounted || load != _loads) return;
    setState(() => _local = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final config = widget.config;
    final size = MediaQuery.sizeOf(context);
    final appearance =
        widget.appearance ?? ChatAppearanceScope.maybeOf(context);
    final presetWins = appearance?.hasRoomPreset ?? false;
    final url = presetWins ? null : config.wallpaperUrl;
    final local = presetWins ? null : _local;
    final preset = wallpaperPresetById(appearance?.preset);
    final colors = preset.colors;
    final blur = config.wallpaperBlur ?? 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: colors == null
                ? tokens.wallG
                : LinearGradient(
                    begin: const Alignment(-0.34, -0.94),
                    end: const Alignment(0.34, 0.94),
                    colors: colors,
                  ),
          ),
        ),
        if (local != null)
          Opacity(
            opacity: config.wallpaperOpacity ?? 0.5,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: Image.memory(
                local,
                key: ChatWallpaper.localImageKey,
                fit: BoxFit.cover,
                cacheWidth: math.min(size.width * 2, 2048).round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          )
        else if (url == null)
          RepaintBoundary(
            key: ChatWallpaper.dotsKey,
            child: CustomPaint(painter: WallpaperDots(tokens.dot2)),
          )
        else
          Opacity(
            opacity: config.wallpaperOpacity ?? 0.5,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: MxcImage(
                client: widget.client,
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
