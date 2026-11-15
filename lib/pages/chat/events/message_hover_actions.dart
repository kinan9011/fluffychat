// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:material_ui/material_ui.dart';

/// Desktop hover actions (DESIGN.md 12): react, reply and more, at the far
/// end of the message row. Touch devices never hover, so nothing shows there.
class MessageHoverActions extends StatelessWidget {
  final bool enabled;
  final bool outgoing;
  final VoidCallback onReact;
  final VoidCallback onReply;
  final VoidCallback onMore;
  final Widget child;

  const MessageHoverActions({
    required this.enabled,
    required this.outgoing,
    required this.onReact,
    required this.onReply,
    required this.onMore,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return HoverBuilder(
      builder: (context, hovered) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (hovered && enabled)
            PositionedDirectional(
              top: 0,
              start: outgoing ? 4 : null,
              end: outgoing ? null : 4,
              child: GlassSurface(
                key: const Key('message_hover_actions'),
                borderRadius: BorderRadius.circular(22),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (icon, label, onTap) in [
                      (Icons.add_reaction_rounded, l10n.moreReactions, onReact),
                      (Icons.reply_rounded, l10n.reply, onReply),
                      (Icons.more_horiz_rounded, l10n.moreOptions, onMore),
                    ])
                      IconButton(
                        icon: Icon(icon, size: 20),
                        tooltip: label,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onTap,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
