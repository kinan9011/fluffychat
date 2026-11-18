// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/glass_policy.dart';
import 'package:fluffychat/widgets/settings/settings_segmented.dart';
import 'package:material_ui/material_ui.dart';

/// Auto, full or lite glass (blur on, or solid surfaces).
class GlassModeRow extends StatelessWidget {
  const GlassModeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: AppSettings.glassMode.listenable,
      builder: (context, _, _) => Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 8),
              child: Text(
                l10n.glassEffects,
                style: TextStyle(
                  color: tokens.fg,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SettingsSegmented<GlassMode>(
              items: [
                (GlassMode.auto, l10n.glassEffectsAuto),
                (GlassMode.full, l10n.glassEffectsFull),
                (GlassMode.lite, l10n.glassEffectsLite),
              ],
              value: GlassMode.parse(AppSettings.glassMode.value),
              onChanged: (mode) => AppSettings.glassMode.setItem(mode.name),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                l10n.glassEffectsDescription,
                style: TextStyle(color: tokens.mut, fontSize: AppSpacing.l - 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
