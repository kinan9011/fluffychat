// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:material_ui/material_ui.dart';

class ChatsBadge extends StatelessWidget {
  final Widget child;
  final int count;

  const ChatsBadge({required this.child, required this.count, super.key});

  static String semanticsLabel(AppTab tab, int chatsBadge, L10n l10n) =>
      tab == AppTab.chats && chatsBadge > 0
      ? l10n.unreadChatsTab(chatsBadge)
      : tab.label(l10n);

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final tokens = AppTokens.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: -4,
          end: -6,
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.acc,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: tokens.bg, width: 2),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  color: tokens.onacc,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
