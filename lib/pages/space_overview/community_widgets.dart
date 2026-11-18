// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The top of a community (DESIGN S6): a banner made from the colour of the
/// space (spaces have no banner image in Matrix) and the avatar overlapping
/// it.
class CommunityBanner extends StatelessWidget {
  final String spaceId;
  final String title;
  final Uri? avatar;
  final Client client;
  final VoidCallback onBack;
  final Widget? trailing;

  const CommunityBanner({
    required this.spaceId,
    required this.title,
    required this.avatar,
    required this.client,
    required this.onBack,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final trailing = this.trailing;
    final color = spaceId.nameColor(Theme.of(context).brightness);
    return SizedBox(
      height: 170 + 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 170,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.38),
                  color.withValues(alpha: 0.12),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            start: 4,
            top: 4,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              style: IconButton.styleFrom(
                backgroundColor: tokens.glass,
                minimumSize: const Size(44, 44),
              ),
              icon: Icon(Icons.arrow_back_rounded, color: tokens.fg),
            ),
          ),
          if (trailing != null)
            PositionedDirectional(end: 4, top: 4, child: trailing),
          PositionedDirectional(
            start: 18,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: tokens.bg,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Avatar(
                mxContent: avatar,
                name: title,
                size: 76,
                colorSeed: spaceId,
                client: client,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The announcements room as a card: last message and who may post. The copy
/// says what this is in Matrix terms: a group where only moderators and
/// admins can post.
class AnnouncementsCard extends StatelessWidget {
  final String title;
  final String? preview;
  final DateTime? time;
  final bool userCanPost;
  final VoidCallback onTap;

  const AnnouncementsCard({
    required this.title,
    required this.preview,
    required this.time,
    required this.userCanPost,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final preview = this.preview;
    final time = this.time;
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
      child: Semantics(
        button: true,
        label: '$title, ${preview ?? ''}, ${l10n.communityOnlyModeratorsPost}',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: tokens.surf,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tokens.acc,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.campaign_outlined,
                      size: 24,
                      color: tokens.onacc,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.fg,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (time != null)
                              Text(
                                time.localizedTimeShort(context),
                                style: TextStyle(
                                  color: tokens.mut,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        if (preview != null)
                          Text(
                            preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.fg,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        Row(
                          spacing: 4,
                          children: [
                            Icon(
                              userCanPost
                                  ? Icons.edit_outlined
                                  : Icons.lock_outline_rounded,
                              size: 14,
                              color: tokens.mut,
                            ),
                            Expanded(
                              child: Text(
                                l10n.communityOnlyModeratorsPost,
                                style: TextStyle(
                                  color: tokens.mut,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
