// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/retention/default_retention.dart';
import 'package:fluffychat/utils/retention/retention_labels.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:material_ui/material_ui.dart';

String defaultRetentionLabel(L10n l10n, int seconds) => seconds == 0
    ? l10n.retentionOff
    : formatRetention(l10n, Duration(seconds: seconds));

Future<void> showDefaultRetentionSheet(BuildContext context) =>
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (_) => const DefaultRetentionSheet(),
    );

/// Picks the timer new chats start with (the privacy page row).
class DefaultRetentionSheet extends StatelessWidget {
  const DefaultRetentionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSettingsLayout.sideMargin,
          AppSpacing.xl,
          AppSettingsLayout.sideMargin,
          AppSpacing.xxl,
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: AppSettings.defaultDisappearSeconds.listenable,
          builder: (context, _, _) {
            final current = DefaultRetention.normalize(
              AppSettings.defaultDisappearSeconds.value,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: Text(
                    l10n.defaultDisappearTimer,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SettingsGroup(
                  footer: l10n.defaultRetentionNote,
                  rows: [
                    for (final seconds in DefaultRetention.allowedSeconds)
                      SettingsRow(
                        key: ValueKey('default_retention_$seconds'),
                        title: defaultRetentionLabel(l10n, seconds),
                        showChevron: false,
                        trailing: seconds == current
                            ? Icon(
                                Icons.check_rounded,
                                color: tokens.acc,
                                semanticLabel: null,
                              )
                            : null,
                        onTap: () => AppSettings.defaultDisappearSeconds
                            .setItem(seconds)
                            .then((_) {
                              if (context.mounted) Navigator.of(context).pop();
                            }),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
