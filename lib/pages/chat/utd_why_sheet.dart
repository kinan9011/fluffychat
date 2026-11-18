// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum UtdWhyAction { verify, restore }

/// "Why can't I read this?" (DESIGN.md C8). Static copy only: an
/// undecryptable event carries nothing we can trust, so nothing of the event
/// (body, sender name) is shown. Both actions open the existing key backup
/// flow, which asks the user for their own passphrase or recovery key. This
/// never trusts a device by itself.
Future<void> showUtdWhySheet(BuildContext context, Event event) async {
  final router = GoRouter.of(context);
  unawaited(
    event.requestKey().catchError(
      (Object _) => Logs().d('Unable to request the key of an event'),
    ),
  );
  final action = await showAdaptiveBottomSheet<UtdWhyAction>(
    context: context,
    builder: (context) => const UtdWhySheet(),
  );
  if (action == null) return;
  await router.push('/backup');
}

class UtdWhySheet extends StatelessWidget {
  const UtdWhySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final reasons = [
      (
        Icons.history_rounded,
        l10n.utdReasonJoinedTitle,
        l10n.utdReasonJoinedBody,
      ),
      (Icons.devices_rounded, l10n.utdReasonKeysTitle, l10n.utdReasonKeysBody),
      (
        Icons.gpp_maybe_rounded,
        l10n.utdReasonUnverifiedTitle,
        l10n.utdReasonUnverifiedBody,
      ),
    ];
    return Material(
      color: tokens.surf,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.only(
            start: 16,
            end: 16,
            bottom: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsetsDirectional.only(top: 10, bottom: 14),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 4,
                  end: 4,
                  bottom: 4,
                ),
                child: Text(
                  l10n.whyCantIReadThis,
                  style: TextStyle(
                    color: tokens.fg,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 4,
                  end: 4,
                  bottom: 12,
                ),
                child: Text(
                  l10n.utdIntro,
                  style: TextStyle(color: tokens.mut, fontSize: 13.5),
                ),
              ),
              for (final (icon, title, body) in reasons)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tokens.surf2,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, size: 20, color: tokens.acc),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: tokens.fg,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              body,
                              style: TextStyle(color: tokens.mut, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              _SheetButton(
                key: const Key('utd_verify_button'),
                icon: Icons.verified_user_rounded,
                label: l10n.verifyThisDevice,
                background: tokens.acc,
                foreground: tokens.onacc,
                onTap: () => Navigator.of(context).pop(UtdWhyAction.verify),
              ),
              const SizedBox(height: 8),
              _SheetButton(
                key: const Key('utd_restore_button'),
                icon: Icons.cloud_download_rounded,
                label: l10n.restoreFromKeyBackup,
                background: tokens.surf2,
                foreground: tokens.fg,
                onTap: () => Navigator.of(context).pop(UtdWhyAction.restore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(26),
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            Icon(icon, size: 20, color: foreground),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
