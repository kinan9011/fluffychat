// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/glass_policy.dart';
import 'package:fluffychat/utils/scheduling/send_options.dart';
import 'package:fluffychat/widgets/glass_menu.dart';
import 'package:material_ui/material_ui.dart';

({IconData icon, String label}) _entry(
  L10n l10n,
  SendOption option,
  String? partnerName,
) => switch (option) {
  SendOption.silent => (
    icon: Icons.notifications_off_rounded,
    label: l10n.sendWithoutSound,
  ),
  SendOption.schedule => (
    icon: Icons.schedule_send_rounded,
    label: l10n.scheduleMessage,
  ),
  SendOption.whenOnline => (
    icon: Icons.person_rounded,
    label: l10n.sendWhenOnline(partnerName ?? ''),
  ),
};

/// Glass card above the send button, [anchor] is the button, with the chat
/// dimmed and blurred behind it (mockup screen 03).
Future<SendOption?> showSendOptionsMenu(
  BuildContext context, {
  required List<SendOption> options,
  required Rect anchor,
  String? partnerName,
}) => showGeneralDialog<SendOption>(
  context: context,
  barrierDismissible: true,
  barrierLabel: L10n.of(context).close,
  barrierColor: Colors.transparent,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 120),
  pageBuilder: (dialogContext, _, _) {
    final l10n = L10n.of(dialogContext);
    final tokens = AppTokens.of(dialogContext);
    final screen = MediaQuery.sizeOf(dialogContext);
    final rtl = Directionality.of(dialogContext) == TextDirection.rtl;
    final dim = ColoredBox(
      color: AppTokens.overlay(0.35),
      child: const SizedBox.expand(),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: glassIsSolidNow(context)
                ? dim
                : BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: AppSchedule.overlayBlur,
                      sigmaY: AppSchedule.overlayBlur,
                    ),
                    child: dim,
                  ),
          ),
        ),
        Positioned(
          bottom: screen.height - anchor.top + AppSchedule.menuGap,
          left: rtl ? anchor.left : null,
          right: rtl ? null : screen.width - anchor.right,
          child: GlassMenuCard(
            width: AppSchedule.menuWidth,
            children: [
              for (final (i, option) in options.indexed)
                GlassMenuRow(
                  autofocus: i == 0,
                  icon: _entry(l10n, option, partnerName).icon,
                  label: _entry(l10n, option, partnerName).label,
                  iconColor: tokens.acc,
                  minHeight: AppSchedule.menuRow,
                  onTap: () => Navigator.of(dialogContext).pop(option),
                ),
              if (options.contains(SendOption.silent))
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
                  child: Text(
                    l10n.sendSilentlyNote,
                    style: TextStyle(color: tokens.mut, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  },
);
