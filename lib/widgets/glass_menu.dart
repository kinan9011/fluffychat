// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:material_ui/material_ui.dart';

/// Glass menu card (DESIGN.md 7.16): radius 22, blur 24, menu shadow.
class GlassMenuCard extends StatelessWidget {
  final List<Widget> children;
  final double width;
  final double? maxHeight;
  final bool solid;

  const GlassMenuCard({
    required this.children,
    this.width = AppChat.menuWidth,
    this.maxHeight,
    this.solid = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: GlassSurface(
      blur: 24,
      solid: solid,
      borderRadius: BorderRadius.circular(AppRadius.menu),
      shadows: AppElevation.menu,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(
                0,
                (maxHeight ?? double.infinity) - 2 * AppSpacing.xs,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    ),
  );
}

class GlassMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool autofocus;
  final bool showDivider;

  const GlassMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.autofocus = false,
    this.showDivider = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = destructive ? tokens.red : tokens.fg;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: tokens.line))
              : null,
        ),
        child: InkWell(
          autofocus: autofocus,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                spacing: AppSpacing.xxl,
                children: [
                  Icon(icon, size: 22, color: color),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
