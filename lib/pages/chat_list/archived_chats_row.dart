// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

class ArchivedChatsRow extends StatelessWidget {
  static const maxNames = 3;

  final List<String> names;
  final int count;
  final VoidCallback onTap;

  const ArchivedChatsRow({
    required this.names,
    required this.count,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final shown = names.take(maxNames).join(', ');
    final more = count - maxNames;
    final subtitle = more > 0 ? '$shown, ${l10n.andCountMore(more)}' : shown;
    return Semantics(
      button: true,
      label: '${l10n.archivedChats}, $subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: tokens.surf2,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                spacing: 12,
                children: [
                  SizedBox(
                    width: 54,
                    height: 40,
                    child: Icon(
                      Icons.inventory_2_rounded,
                      size: 26,
                      color: tokens.mut,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.archivedChats,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tokens.mut, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
