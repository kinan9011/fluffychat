// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// No consumer until the shell redesign (W03) adopts it.
// ignore_for_file: unused-code, unused-files

import 'dart:ui';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

/// The only glass implementation (DESIGN.md 6.1): blur(20) saturate(1.4), a
/// hairline border and a shadow. Every blurred surface in the app must use
/// this widget so the backdrop-filter cost can be tuned in one place.
class GlassSurface extends StatelessWidget {
  @visibleForTesting
  static const surfaceKey = ValueKey('glass_surface');

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final double blur;
  final List<BoxShadow>? shadows;

  /// Forces the opaque fallback.
  final bool solid;

  const GlassSurface({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.card)),
    this.blur = 20,
    this.shadows,
    this.solid = false,
    super.key,
  });

  /// CSS `saturate(1.4)`: each row sums to 1 so greys keep their value and
  /// luminance is preserved (weights 0.213/0.715/0.072).
  @visibleForTesting
  static const saturateMatrix = <double>[
    1.3148, -0.286, -0.0288, 0, 0, //
    -0.0852, 1.114, -0.0288, 0, 0, //
    -0.0852, -0.286, 1.3712, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Flutter has no "reduce transparency" platform flag, so we follow the
    // closest OS signal (increased contrast) plus our own setting.
    final opaque =
        solid ||
        MediaQuery.highContrastOf(context) ||
        AppSettings.reduceTransparency.value;
    final surface = DecoratedBox(
      key: surfaceKey,
      decoration: BoxDecoration(
        color: opaque ? tokens.surf : tokens.glass,
        borderRadius: borderRadius,
        border: Border.all(color: tokens.glassBd),
      ),
      child: child,
    );
    final radius = borderRadius.resolve(Directionality.of(context));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipPath(
            clipper: _OutsideRRectClipper(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: shadows ?? AppElevation.glass(tokens.shadow),
              ),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: radius,
          child: opaque
              ? surface
              : BackdropFilter(
                  filter: ImageFilter.compose(
                    outer: const ColorFilter.matrix(saturateMatrix),
                    inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  ),
                  child: surface,
                ),
        ),
      ],
    );
  }
}

/// CSS box-shadow is not painted under the box, which matters because the
/// glass fill is translucent.
class _OutsideRRectClipper extends CustomClipper<Path> {
  final BorderRadius radius;

  const _OutsideRRectClipper(this.radius);

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect((Offset.zero & size).inflate(200)),
    Path()..addRRect(radius.toRRect(Offset.zero & size)),
  );

  @override
  bool shouldReclip(_OutsideRRectClipper oldClipper) =>
      oldClipper.radius != radius;
}
