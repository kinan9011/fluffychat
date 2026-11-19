// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_config.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/branding/support_links.dart';
import 'package:odango/utils/launch_web_url.dart';
import 'package:odango/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

Future<void> showSupportDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SupportDialog());

class SupportDialog extends StatelessWidget {
  const SupportDialog({super.key, this.links, this.launch = launchWebUrl});

  final SupportLinks? links;
  final Future<bool> Function(String url) launch;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final links = this.links ?? SupportLinks.fromSettings();
    final koFi = links.koFi;
    final buyMeACoffee = links.buyMeACoffee;
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.favorite_rounded, color: theme.colorScheme.error),
      title: Text(l10n.supportOdango, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(l10n.supportOdangoBody, textAlign: TextAlign.center),
            if (koFi != null)
              _SupportButton(
                icon: Icons.coffee_rounded,
                label: l10n.supportKoFi,
                onPressed: () => launch(koFi.toString()),
              ),
            if (buyMeACoffee != null)
              _SupportButton(
                icon: Icons.local_cafe_rounded,
                label: l10n.supportBuyMeACoffee,
                onPressed: () => launch(buyMeACoffee.toString()),
              ),
            if (!links.hasAny)
              Text(
                l10n.supportLinksNotSet,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => launch(AppConfig.upstreamRepoUrl),
              child: Text(l10n.supportUpstreamSource),
            ),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}
