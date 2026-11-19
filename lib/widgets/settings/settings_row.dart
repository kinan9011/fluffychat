// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';

/// 32 px icon tile of a settings row (accent tint or neutral).
class SettingsIconTile extends StatelessWidget {
  final IconData icon;
  final bool neutral;
  final Color? color;

  const SettingsIconTile(
    this.icon, {
    this.neutral = false,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: AppSettingsLayout.tile,
      height: AppSettingsLayout.tile,
      decoration: BoxDecoration(
        color: neutral ? tokens.surf2 : tokens.accs,
        borderRadius: BorderRadius.circular(AppSettingsLayout.tileRadius),
      ),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: Icon(
          icon,
          size: 19,
          color: color ?? (neutral ? tokens.fg : tokens.acc),
        ),
      ),
    );
  }
}

/// One row of a [SettingsGroup]: 50 px (62 px with a subtitle), icon tile,
/// value text and chevron (DESIGN.md 7.14).
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool neutralTile;
  final bool showChevron;

  const SettingsRow({
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.neutralTile = false,
    this.showChevron = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final subtitle = this.subtitle;
    final value = this.value;
    final icon = this.icon;
    final titleColor = destructive ? tokens.red : tokens.fg;
    final label = [title, ?subtitle, ?value].join(', ');
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: subtitle == null
                ? AppSettingsLayout.rowHeight
                : AppSettingsLayout.rowHeightSub,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSettingsLayout.rowPadding,
              vertical: 6,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox(
                    width: AppSettingsLayout.tile,
                    height: AppSettingsLayout.tile,
                    child: leading,
                  ),
                  const SizedBox(width: AppSpacing.l),
                ] else if (icon != null) ...[
                  SettingsIconTile(
                    icon,
                    neutral: neutralTile,
                    color: destructive ? tokens.red : null,
                  ),
                  const SizedBox(width: AppSpacing.l),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: tokens.mut,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.mut, fontSize: 13),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ] else if (showChevron && onTap != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: tokens.mut,
                    textDirection: Directionality.of(context),
                    semanticLabel: null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
