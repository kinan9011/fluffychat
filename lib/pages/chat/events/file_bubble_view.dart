// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';

/// 46 px download circle, file name and "size · TYPE" (DESIGN.md 7.11). The
/// file name belongs to the sender: one plain line.
class FileBubbleView extends StatelessWidget {
  final String filename;
  final String meta;
  final bool outgoing;
  final Widget? leading;
  final VoidCallback? onTap;

  const FileBubbleView({
    required this.filename,
    required this.meta,
    required this.outgoing,
    this.leading,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = BubbleColors.of(tokens, outgoing: outgoing);
    return Semantics(
      button: true,
      label: '$filename, $meta',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 12, 6),
            child: Row(
              spacing: 12,
              children: [
                leading ??
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.accentFill,
                      ),
                      child: Icon(
                        Icons.arrow_downward_rounded,
                        size: 24,
                        color: colors.onAccent,
                      ),
                    ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(
                        filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
