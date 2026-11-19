// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/widgets/settings/settings_row.dart';

/// Row with the 46 x 28 switch of DESIGN.md 7.14.
class SettingsToggleRow extends StatelessWidget {
  @visibleForTesting
  static const switchKey = ValueKey('settings_switch');
  @visibleForTesting
  static const knobKey = ValueKey('settings_switch_knob');
  @visibleForTesting
  static const knobAlignKey = ValueKey('settings_switch_align');
  @visibleForTesting
  static const opacityKey = ValueKey('settings_toggle_opacity');

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingsToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final onChanged = this.onChanged;
    final icon = this.icon;
    final subtitle = this.subtitle;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: title,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged(!value) : null,
      child: Opacity(
        key: opacityKey,
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
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
                  if (icon != null) ...[
                    SettingsIconTile(icon),
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
                            color: tokens.fg,
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
                  const SizedBox(width: AppSpacing.m),
                  AnimatedContainer(
                    key: switchKey,
                    duration: duration,
                    curve: Curves.easeOut,
                    width: AppSettingsLayout.switchWidth,
                    height: AppSettingsLayout.switchHeight,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: value ? tokens.acc : tokens.line,
                      borderRadius: BorderRadius.circular(
                        AppSettingsLayout.switchHeight / 2,
                      ),
                    ),
                    child: AnimatedAlign(
                      key: knobAlignKey,
                      duration: duration,
                      curve: Curves.easeOut,
                      alignment: value
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Container(
                        key: knobKey,
                        width: AppSettingsLayout.knob,
                        height: AppSettingsLayout.knob,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFFFFF),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
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

/// A [SettingsToggleRow] bound to a boolean [AppSettings] key.
class AppSettingToggleRow extends StatelessWidget {
  final AppSettings<bool?> setting;
  final bool defaultValue;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;

  const AppSettingToggleRow({
    required this.setting,
    required this.title,
    this.defaultValue = false,
    this.icon,
    this.subtitle,
    this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: setting.listenable,
    builder: (context, _, _) => SettingsToggleRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: setting.value ?? setting.defaultValue ?? defaultValue,
      onChanged: (value) async {
        onChanged?.call(value);
        await setting.setItem(value);
      },
    ),
  );
}
