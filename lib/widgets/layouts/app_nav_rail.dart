// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:material_ui/material_ui.dart';

class AppNavRail extends StatelessWidget {
  final List<AppTab> tabs;
  final AppTab? selected;
  final ValueChanged<AppTab> onSelect;
  final Widget profileAvatar;
  final int accountCount;

  const AppNavRail({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.profileAvatar,
    this.accountCount = 1,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.mainNavigation,
      child: Material(
        color: tokens.surf,
        child: SizedBox(
          width: FluffyThemes.navRailWidth,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Column(
                spacing: AppSpacing.m,
                children: [
                  _RailButton(
                    label: AppTab.profile.label(l10n),
                    selected: selected == AppTab.profile,
                    ring: true,
                    onTap: () => onSelect(AppTab.profile),
                    child: Badge(
                      isLabelVisible: accountCount > 1,
                      label: Text('$accountCount'),
                      backgroundColor: tokens.acc,
                      textColor: tokens.onacc,
                      child: profileAvatar,
                    ),
                  ),
                  for (final tab in tabs)
                    if (tab != AppTab.profile)
                      _RailButton(
                        label: tab.label(l10n),
                        selected: tab == selected,
                        onTap: () => onSelect(tab),
                        child: Icon(
                          tab == selected ? tab.activeIcon : tab.icon,
                          size: 24,
                          color: tab == selected ? tokens.onacc : tokens.mut,
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

class _RailButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool ring;
  final VoidCallback onTap;
  final Widget child;

  const _RailButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.ring = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: ring || !selected ? Colors.transparent : tokens.acc,
          shape: ring
              ? CircleBorder(
                  side: BorderSide(
                    color: selected ? tokens.acc : Colors.transparent,
                    width: 2,
                  ),
                )
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(dimension: 48, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

class AppTabStrip extends StatelessWidget {
  final List<AppTab> tabs;
  final AppTab? selected;
  final ValueChanged<AppTab> onSelect;
  final Widget profileAvatar;

  const AppTabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.profileAvatar,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.mainNavigation,
      child: Material(
        color: tokens.bg,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Row(
              children: [
                for (final tab in tabs)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: tab == selected,
                      label: tab.label(l10n),
                      onTap: () => onSelect(tab),
                      excludeSemantics: true,
                      child: Tooltip(
                        message: tab.label(l10n),
                        child: Material(
                          color: tab == selected
                              ? tokens.accs
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onSelect(tab),
                            child: SizedBox(
                              height: 44,
                              child: Center(
                                child: tab == AppTab.profile
                                    ? SizedBox.square(
                                        dimension: 26,
                                        child: profileAvatar,
                                      )
                                    : Icon(
                                        tab == selected
                                            ? tab.activeIcon
                                            : tab.icon,
                                        size: 24,
                                        color: tab == selected
                                            ? tokens.acc
                                            : tokens.fg,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
