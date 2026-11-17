// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_wallpaper.dart';
import 'package:fluffychat/pages/settings_appearance/settings_appearance.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/appearance/chat_appearance.dart';
import 'package:fluffychat/utils/appearance/wallpaper_store.dart';
import 'package:fluffychat/utils/chat/bubble_shape.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:fluffychat/widgets/settings/settings_segmented.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:material_ui/material_ui.dart';

class SettingsAppearanceView extends StatelessWidget {
  const SettingsAppearanceView(this.controller, {super.key});

  final SettingsAppearanceController controller;

  static String presetName(L10n l10n, String id) => switch (id) {
    'meadow' => l10n.wallpaperPresetMeadow,
    'sunset' => l10n.wallpaperPresetSunset,
    'night' => l10n.wallpaperPresetNight,
    'paper' => l10n.wallpaperPresetPaper,
    _ => l10n.wallpaperPresetDefault,
  };

  static String cornersName(L10n l10n, BubbleCorners corners) =>
      switch (corners) {
        BubbleCorners.sharp => l10n.bubbleCornersSharp,
        BubbleCorners.standard => l10n.bubbleCornersStandard,
        BubbleCorners.round => l10n.bubbleCornersRound,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final room = controller.room;
    final inRoom = controller.scope == AppearanceScope.room && room != null;
    final resolved = controller.resolved;
    final roomName = room == null
        ? null
        : safeDisplayText(
            room.getLocalizedDisplayname(MatrixLocals(l10n)),
            maxGraphemes: 40,
          );
    final client = Matrix.of(context).client;
    final textScale =
        controller.fontSize / SettingsAppearanceController.baseFontSize;
    return SettingsScaffold(
      title: l10n.chatAppearance,
      children: [
        if (room != null && roomName != null)
          SettingsSegmented<AppearanceScope>(
            items: [
              (AppearanceScope.all, l10n.appearanceScopeAll),
              (AppearanceScope.room, l10n.appearanceScopeChat(roomName)),
            ],
            value: controller.scope,
            onChanged: controller.setScope,
          ),
        _Preview(
          appearance: resolved,
          config: client.applicationAccountConfig,
          textScale: textScale,
          store: controller.store,
        ),
        if (!inRoom)
          SettingsGroup(
            header: l10n.sectionTheme,
            rows: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: SettingsSegmented<ThemeMode>(
                  items: [
                    (ThemeMode.system, l10n.systemTheme),
                    (ThemeMode.light, l10n.lightTheme),
                    (ThemeMode.dark, l10n.darkTheme),
                  ],
                  value: controller.currentTheme,
                  onChanged: controller.switchTheme,
                ),
              ),
            ],
          ),
        _SectionLabel(l10n.sectionWallpaper),
        _WallpaperRow(controller: controller, selected: resolved.preset),
        if (!inRoom && LocalWallpaperStore.supported)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 18,
              end: 18,
              bottom: 12,
            ),
            child: Text(
              l10n.wallpaperLocalNote,
              style: TextStyle(color: tokens.mut, fontSize: 12.5, height: 1.4),
            ),
          ),
        if (!inRoom && controller.hasImageWallpaper) ...[
          SettingsGroup(
            rows: [
              _SliderRow(
                label: l10n.opacity,
                value: controller.wallpaperOpacity,
                onChanged: controller.updateWallpaperOpacity,
                onChangeEnd: controller.saveWallpaperOpacity,
              ),
              _SliderRow(
                label: l10n.blur,
                value: controller.wallpaperBlur,
                onChanged: controller.updateWallpaperBlur,
                onChangeEnd: controller.saveWallpaperBlur,
              ),
              SettingsRow(
                icon: Icons.hide_image_rounded,
                title: l10n.wallpaperRemove,
                destructive: true,
                showChevron: false,
                onTap: controller.removeWallpaper,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s),
        _SectionLabel(l10n.sectionAccent),
        DynamicColorBuilder(
          builder: (light, dark) {
            final systemColor = Theme.of(context).brightness == Brightness.light
                ? light?.primary
                : dark?.primary;
            final swatches = SettingsAppearanceController.accentSwatches(
              systemColor,
            );
            final checked = SettingsAppearanceController.checkedSwatch(
              swatches,
              resolved.accentHue.toInt(),
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, AppSpacing.xxxl),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final (i, color) in swatches.indexed)
                    _AccentSwatch(
                      color: color,
                      checked: checked == i,
                      onTap: () => controller.setChatColor(color),
                    ),
                ],
              ),
            );
          },
        ),
        if (!inRoom) ...[
          _SectionLabel(l10n.sectionTextSize),
          SettingsGroup(
            rows: [
              _SliderRow(
                label: l10n.textSizeValue(controller.fontSize),
                value: controller.fontSize.toDouble(),
                min: SettingsAppearanceController.minFontSize.toDouble(),
                max: SettingsAppearanceController.maxFontSize.toDouble(),
                divisions:
                    SettingsAppearanceController.maxFontSize -
                    SettingsAppearanceController.minFontSize,
                onChanged: (v) => controller.changeFontSize(v.round()),
              ),
            ],
          ),
        ],
        _SectionLabel(l10n.sectionBubbleCorners),
        SettingsSegmented<BubbleCorners>(
          items: [
            for (final corners in BubbleCorners.values)
              (corners, cornersName(l10n, corners)),
          ],
          value: resolved.corners,
          onChanged: controller.setBubbleCorners,
        ),
        if (inRoom && controller.roomAppearance != null)
          SettingsGroup(
            rows: [
              SettingsRow(
                icon: Icons.restart_alt_rounded,
                title: l10n.appearanceUseGlobal,
                showChevron: false,
                onTap: controller.useGlobalSettings,
              ),
            ],
          ),
        if (!inRoom)
          SettingsGroup(
            rows: [
              AppSettingToggleRow(
                icon: Icons.blur_off_rounded,
                title: l10n.reduceTransparency,
                subtitle: l10n.reduceTransparencyDescription,
                setting: AppSettings.reduceTransparency,
                defaultValue: AppSettings.reduceTransparency.defaultValue,
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            l10n.appearanceLocalNote,
            style: TextStyle(color: tokens.mut, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 18, end: 18, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppTokens.of(context).mut,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.48,
      ),
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.appearance,
    required this.config,
    required this.textScale,
    required this.store,
  });

  final ResolvedAppearance appearance;
  final ApplicationAccountConfig config;
  final double textScale;
  final LocalWallpaperStore? store;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = dark
        ? AppTokens.dark(hue: appearance.accentHue)
        : AppTokens.light(hue: appearance.accentHue);
    final incoming = bubbleRadius(
      outgoing: false,
      tail: true,
      corners: appearance.corners,
    );
    final outgoing = bubbleRadius(
      outgoing: true,
      tail: true,
      corners: appearance.corners,
    );
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Semantics(
        container: true,
        label: l10n.chatAppearance,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: SizedBox(
            height: 170,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ChatWallpaper(
                  config: config,
                  appearance: appearance,
                  store: store,
                  client: Matrix.of(context).client,
                ),
                MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: 6,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _PreviewBubble(
                            text: l10n.appearancePreviewIncoming,
                            fill: tokens.surf,
                            color: tokens.fg,
                            radius: incoming.resolve(
                              Directionality.of(context),
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _PreviewBubble(
                            text: l10n.appearancePreviewOutgoing,
                            fill: tokens.outS,
                            color: tokens.outFg,
                            radius: outgoing.resolve(
                              Directionality.of(context),
                            ),
                          ),
                        ),
                      ],
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

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.text,
    required this.fill,
    required this.color,
    required this.radius,
  });

  final String text;
  final Color fill;
  final Color color;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.6,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 16, height: 1.35),
        ),
      ),
    ),
  );
}

class _WallpaperRow extends StatelessWidget {
  const _WallpaperRow({required this.controller, required this.selected});

  final SettingsAppearanceController controller;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final imageActive =
        controller.scope == AppearanceScope.all && controller.hasImageWallpaper;
    final canAdd =
        LocalWallpaperStore.supported &&
        controller.scope == AppearanceScope.all;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, AppSpacing.xxl),
      child: Wrap(
        spacing: 10,
        runSpacing: 14,
        children: [
          for (final preset in wallpaperPresets)
            Semantics(
              button: true,
              selected: !imageActive && preset.id == selected,
              label: SettingsAppearanceView.presetName(l10n, preset.id),
              excludeSemantics: true,
              onTap: () => controller.setWallpaperPreset(preset.id),
              child: GestureDetector(
                onTap: () => controller.setWallpaperPreset(preset.id),
                child: _Swatch(
                  key: ValueKey('wallpaper_${preset.id}'),
                  checked: !imageActive && preset.id == selected,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: const Alignment(-0.34, -0.94),
                      end: const Alignment(0.34, 0.94),
                      colors: preset.colors ?? tokens.wallG.colors,
                    ),
                  ),
                ),
              ),
            ),
          if (canAdd)
            Semantics(
              button: true,
              selected: imageActive,
              label: l10n.wallpaperAddPhoto,
              excludeSemantics: true,
              onTap: controller.pickCustomWallpaper,
              child: GestureDetector(
                onTap: controller.pickCustomWallpaper,
                child: _Swatch(
                  key: const ValueKey('wallpaper_custom'),
                  checked: imageActive,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tokens.mut, width: 1.5),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_rounded,
                    color: tokens.mut,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.checked,
    required this.decoration,
    this.child,
    super.key,
  });

  final bool checked;
  final BoxDecoration decoration;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: 52,
      height: 72,
      alignment: Alignment.center,
      decoration: decoration.copyWith(
        boxShadow: checked
            ? [
                BoxShadow(color: tokens.acc, spreadRadius: 4.5),
                BoxShadow(color: tokens.bg, spreadRadius: 2.5),
              ]
            : null,
      ),
      child: checked && child == null
          ? Icon(Icons.check_rounded, color: tokens.acc)
          : child,
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.checked,
    required this.onTap,
  });

  final Color color;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = '#${color.hexValue.toRadixString(16).toUpperCase()}';
    return Semantics(
      button: true,
      selected: checked,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: checked
                    ? [
                        BoxShadow(color: tokens.fg, spreadRadius: 4.5),
                        BoxShadow(color: tokens.bg, spreadRadius: 2.5),
                      ]
                    : null,
              ),
              child: checked
                  ? const Icon(Icons.check_rounded, color: Color(0xFFFFFFFF))
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSettingsLayout.rowPadding,
        vertical: 4,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                color: tokens.fg,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: divisions == null ? null : value.round().toString(),
              semanticFormatterCallback: (v) => label,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}
