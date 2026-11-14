// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatListTopBar extends StatelessWidget {
  final String title;
  final Widget avatar;
  final VoidCallback onProfile;
  final VoidCallback onSearch;
  final Widget overflow;
  final Widget? spaceChip;
  final SyncStatusUpdate? syncStatus;

  const ChatListTopBar({
    required this.title,
    required this.avatar,
    required this.onProfile,
    required this.onSearch,
    required this.overflow,
    this.spaceChip,
    this.syncStatus,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final status = syncStatus;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 14, 12),
      child: Row(
        spacing: 12,
        children: [
          Semantics(
            button: true,
            label: l10n.openProfile,
            onTap: onProfile,
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onProfile,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [tokens.acc, tokens.ok, tokens.acc],
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.bg,
                  ),
                  child: avatar,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                spaceChip ??
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.48,
                        color: tokens.fg,
                      ),
                    ),
                if (status != null) ...[
                  Text(
                    status.calcLocalizedString(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: tokens.mut),
                  ),
                  const SizedBox(height: 2),
                  LinearProgressIndicator(
                    value: status.progress,
                    minHeight: 2,
                    color: tokens.acc,
                    backgroundColor: tokens.line,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.search,
            onPressed: onSearch,
            iconSize: 25,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: Icon(Icons.search_rounded, color: tokens.fg),
          ),
          overflow,
        ],
      ),
    );
  }
}
