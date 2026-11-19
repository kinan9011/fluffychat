// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat/reaction_summary.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Reactions under a bubble (DESIGN.md 7.6): own reactions accent filled,
/// others on the surface colour. Taps are 44 px, the pill itself 28 px.
class ReactionPills extends StatelessWidget {
  final ReactionSummary summary;
  final bool alignEnd;
  final Client? client;
  final void Function(ReactionEntry entry)? onTap;
  final void Function(ReactionEntry entry)? onLongPress;

  const ReactionPills({
    required this.summary,
    required this.alignEnd,
    this.client,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: AppChat.reactionGap,
      children: [
        for (final entry in summary.entries)
          _Pill(
            entry: entry,
            client: client,
            onTap: onTap == null ? null : () => onTap!(entry),
            onLongPress: onLongPress == null ? null : () => onLongPress!(entry),
          ),
        if (summary.hiddenKeys > 0)
          Center(
            key: const ValueKey('reaction_more'),
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '+${summary.hiddenKeys}',
                style: TextStyle(color: tokens.mut, fontSize: 12.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final ReactionEntry entry;
  final Client? client;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _Pill({
    required this.entry,
    required this.client,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = entry.own ? tokens.onacc : tokens.fg;
    final image = entry.imageUri;
    var text = Characters(entry.key);
    if (text.length > 10) text = text.getRange(0, 9) + Characters('…');
    return Semantics(
      button: true,
      selected: entry.own,
      label: L10n.of(context).reactionPillLabel(
        image == null ? text.toString() : L10n.of(context).customReaction,
        entry.count,
      ),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey('reaction_chip_${entry.key}'),
              height: AppChat.reactionChipHeight,
              constraints: const BoxConstraints(
                minWidth: AppChat.reactionChipMinWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: entry.own ? tokens.acc : tokens.surf,
                borderRadius: BorderRadius.circular(
                  AppChat.reactionChipHeight / 2,
                ),
                border: entry.own ? null : Border.all(color: tokens.line),
              ),
              child: Center(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    if (image != null)
                      MxcImage(
                        client: client,
                        uri: image,
                        width: 18,
                        height: 18,
                        animated: false,
                      )
                    else
                      Text(
                        text.toString(),
                        style: const TextStyle(fontSize: 14),
                      ),
                    if (entry.count > 1)
                      Text(
                        '${entry.count}',
                        style: TextStyle(
                          color: color,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: AppChat.tapTarget - AppChat.reactionChipHeight,
            ),
          ],
        ),
      ),
    );
  }
}
