// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/links/matrix_link_policy.dart';
import 'package:material_ui/material_ui.dart';

/// Shows what a scanned code points at and asks before anything is opened.
/// Returns true only when the user taps Open.
Future<bool> confirmScannedTarget(
  BuildContext context,
  ScannedTarget target,
) async {
  final result = await showAdaptiveBottomSheet<bool>(
    context: context,
    maxHeight: 520,
    builder: (_) => ScanConfirmSheet(target: target),
  );
  return result == true;
}

class ScanConfirmSheet extends StatelessWidget {
  final ScannedTarget target;

  const ScanConfirmSheet({required this.target, super.key});

  static const openKey = ValueKey('scan_confirm_open');
  static const cancelKey = ValueKey('scan_confirm_cancel');

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final sentence = switch (target.kind) {
      ScannedKind.user => l10n.qrOpenUser,
      ScannedKind.room => l10n.qrOpenRoom,
      ScannedKind.alias => l10n.qrOpenAlias,
    };
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: insets),
      child: Material(
        color: tokens.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.qrOpenTitle,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  sentence,
                  style: TextStyle(color: tokens.fg, fontSize: 15, height: 1.4),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.surf2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    target.identifier,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: tokens.fg,
                      fontFamily: AppTypography.monoFamily,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (target.via.isNotEmpty)
                  Text(
                    target.via.join(', '),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: tokens.mut,
                      fontFamily: AppTypography.monoFamily,
                      fontSize: 12,
                    ),
                  ),
                Row(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: cancelKey,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        backgroundColor: tokens.surf2,
                        foregroundColor: tokens.fg,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        l10n.cancel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        key: openKey,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: tokens.acc,
                          foregroundColor: tokens.onacc,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          l10n.open,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
