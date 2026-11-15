// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Amber "Waiting for this message" with a "Why?" link (DESIGN.md 7.5). No
/// text of the event is shown: an undecryptable event has none we can trust.
class UtdBubbleContent extends StatelessWidget {
  final VoidCallback onWhy;

  const UtdBubbleContent({required this.onWhy, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Icon(Icons.lock_clock_rounded, size: 20, color: tokens.warn),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.waitingForThisMessage,
                  style: TextStyle(
                    color: tokens.mut,
                    fontSize: 14.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Semantics(
                  button: true,
                  child: InkWell(
                    onTap: onWhy,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 1,
                        child: Text(
                          l10n.why,
                          style: TextStyle(
                            color: tokens.acc,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
