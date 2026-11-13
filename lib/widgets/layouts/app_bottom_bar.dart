// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:material_ui/material_ui.dart';

class AppBottomBar extends StatelessWidget {
  static const double height = 68;
  static const double sideInset = AppSpacing.xl;
  static const double minBottomInset = AppSpacing.huge;
  static const double _padding = 5;
  static const double _gap = 2;
  static const double _fadeHeight = 120;

  final List<AppTab> tabs;
  final AppTab selected;
  final ValueChanged<AppTab> onSelect;
  final Widget profileAvatar;

  const AppBottomBar({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.profileAvatar,
    super.key,
  });

  static double occupiedHeight(BuildContext context) =>
      height + _bottomInset(context);

  static double _bottomInset(BuildContext context) =>
      max(minBottomInset, MediaQuery.paddingOf(context).bottom);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bottom = _bottomInset(context);
    return SizedBox(
      height: _fadeHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [tokens.bg, tokens.bg.withAlpha(0)],
                    stops: const [0.35, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: sideInset,
            right: sideInset,
            bottom: bottom,
            height: height,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: L10n.of(context).mainNavigation,
              child: GlassSurface(
                borderRadius: BorderRadius.circular(height / 2),
                shadows: AppElevation.bottomBar(tokens.shadow),
                child: Padding(
                  padding: const EdgeInsets.all(_padding),
                  child: Row(
                    spacing: _gap,
                    children: [
                      for (final tab in tabs)
                        Expanded(
                          child: _BarItem(
                            tab: tab,
                            selected: tab == selected,
                            onTap: () => onSelect(tab),
                            profileAvatar: profileAvatar,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  final Widget profileAvatar;

  const _BarItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.profileAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = tab.label(L10n.of(context));
    final color = selected ? tokens.acc : tokens.fg;
    final icon = tab.icon;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? tokens.accs : Colors.transparent,
        borderRadius: BorderRadius.circular(29),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 3,
            children: [
              SizedBox.square(
                dimension: 25,
                child: icon == null
                    ? profileAvatar
                    : Icon(
                        selected ? tab.activeIcon : icon,
                        size: 25,
                        color: color,
                      ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
