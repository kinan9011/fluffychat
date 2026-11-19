// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/settings_homeserver/settings_homeserver.dart';
import 'package:odango/utils/server_capabilities/homeserver_report.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';
import 'package:odango/widgets/matrix.dart';
import 'package:odango/widgets/settings/settings_group.dart';
import 'package:odango/widgets/settings/settings_row.dart';
import 'package:odango/widgets/settings/settings_scaffold.dart';

class SettingsHomeserverView extends StatelessWidget {
  const SettingsHomeserverView(this.controller, {super.key});

  final SettingsHomeserverController controller;

  static IconData featureIcon(ServerFeature feature) => switch (feature) {
    ServerFeature.slidingSync => Icons.bolt_rounded,
    ServerFeature.retention => Icons.timer_rounded,
    ServerFeature.qrLogin => Icons.qr_code_2_rounded,
    ServerFeature.threadNotifications => Icons.forum_rounded,
    ServerFeature.delayedEvents => Icons.schedule_send_rounded,
    ServerFeature.groupCalls => Icons.groups_rounded,
    ServerFeature.serverSideSearchE2ee => Icons.search_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final client = Matrix.of(context).client;
    final info = controller.info;
    final domain = client.userID?.domain ?? info?.domain ?? '';
    final limit = formatUploadLimit(info?.uploadLimitBytes);
    final software = info?.software == null
        ? null
        : '${info!.software} ${info.version ?? ''}'.trim();
    final subtitle = [
      ?software,
      if (limit != null) l10n.homeserverUploadLimit(limit),
    ].join(' · ');
    final online = controller.online;
    return SettingsScaffold(
      title: l10n.settingsHomeserver,
      actions: [
        IconButton(
          key: const ValueKey('homeserver_check_again'),
          tooltip: l10n.checkAgain,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: controller.loading
              ? null
              : () => controller.refresh(force: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        Container(
          margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xxl),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surf,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            spacing: 14,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: tokens.accs,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.dns_rounded, size: 28, color: tokens.acc),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      domain,
                      textDirection: TextDirection.ltr,
                      style: AppTypography.mono.copyWith(
                        color: tokens.fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(color: tokens.mut, fontSize: 13),
                      ),
                  ],
                ),
              ),
              if (controller.loading && !online)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: online ? tokens.ok : tokens.mut,
                    ),
                    Text(
                      online ? l10n.homeserverOnline : l10n.homeserverOffline,
                      style: TextStyle(
                        color: online ? tokens.ok : tokens.mut,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        SettingsGroup(
          header: l10n.homeserverFeatures,
          rows: [
            for (final feature in homeserverFeatureOrder)
              _FeatureRow(
                key: ValueKey('feature_${feature.name}'),
                feature: feature,
                support: controller.caps[feature],
              ),
          ],
          footer: l10n.homeserverChecksNote(AppSettings.applicationName.value),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('share_with_admin'),
              onPressed: controller.shareWithAdmin,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: tokens.acc,
              ),
              child: Text(
                l10n.shareWithAdmin,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        SettingsGroup(
          rows: [
            SettingsRow(
              key: const ValueKey('homeserver_details'),
              icon: Icons.info_rounded,
              title: l10n.moreServerDetails,
              onTap: () => context.go('/settings/homeserver/details'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature, required this.support, super.key});

  final ServerFeature feature;
  final FeatureSupport support;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final (icon, color) = switch (support) {
      FeatureSupport.supported => (Icons.check_circle_rounded, tokens.ok),
      FeatureSupport.partial => (Icons.error_rounded, tokens.warn),
      FeatureSupport.unsupported => (Icons.cancel_rounded, tokens.mut),
      FeatureSupport.unknown => (Icons.help_outline_rounded, tokens.mut),
    };
    final label = supportLabel(l10n, support);
    return SettingsRow(
      icon: SettingsHomeserverView.featureIcon(feature),
      neutralTile: true,
      title: featureTitle(l10n, feature),
      subtitle: featureDescription(l10n, feature),
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Icon(icon, size: 16, color: color),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
