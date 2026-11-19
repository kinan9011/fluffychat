// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat_list/unread_bubble.dart';
import 'package:odango/utils/spaces/space_hierarchy.dart';
import 'package:odango/widgets/avatar.dart';

/// Name, avatar, member count and topic of the space (DESIGN S5, 9.24).
class SpaceHeader extends StatelessWidget {
  final String title;
  final String spaceId;
  final Uri? avatar;
  final String subtitle;
  final String? topic;
  final Client client;

  const SpaceHeader({
    required this.title,
    required this.spaceId,
    required this.avatar,
    required this.subtitle,
    required this.topic,
    required this.client,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final topic = this.topic;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Row(
            spacing: 14,
            children: [
              Avatar(
                mxContent: avatar,
                name: title,
                size: 64,
                colorSeed: spaceId,
                client: client,
                borderRadius: BorderRadius.circular(20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: tokens.mut, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (topic != null)
            Text(
              topic,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mut, fontSize: 14, height: 1.45),
            ),
        ],
      ),
    );
  }
}

class SpaceActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final String? semanticsLabel;

  const SpaceActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.semanticsLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final foreground = primary ? tokens.onacc : tokens.fg;
    final semanticsLabel = this.semanticsLabel;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      value: semanticsLabel == null ? null : label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: primary ? tokens.acc : tokens.surf2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  Icon(icon, size: 19, color: foreground),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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

class SpaceTabsRow extends StatelessWidget {
  final bool joinedSelected;
  final int joinedCount;
  final int suggestedCount;
  final VoidCallback onJoined;
  final VoidCallback onSuggested;

  const SpaceTabsRow({
    required this.joinedSelected,
    required this.joinedCount,
    required this.suggestedCount,
    required this.onJoined,
    required this.onSuggested,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          spacing: 22,
          children: [
            _Tab(
              label: l10n.spaceTabJoined(joinedCount),
              selected: joinedSelected,
              onTap: onJoined,
            ),
            _Tab(
              label: l10n.spaceTabSuggested(suggestedCount),
              selected: !joinedSelected,
              onTap: onSuggested,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? tokens.acc : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? tokens.acc : tokens.mut,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One room or subspace of the overview.
class HierarchyRow extends StatelessWidget {
  final HierarchyChild child;
  final Client client;
  final Room? joined;
  final bool canEnter;
  final bool onTrail;
  final VoidCallback? onTap;
  final VoidCallback onJoin;
  final VoidCallback? onRemove;

  const HierarchyRow({
    required this.child,
    required this.client,
    required this.joined,
    required this.canEnter,
    required this.onTrail,
    required this.onTap,
    required this.onJoin,
    this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final onRemove = this.onRemove;
    final name = child.name ?? child.alias ?? l10n.emptyChat;
    final joined = this.joined;
    final subtitle = child.isSpace
        ? l10n.spaceSubspaceRooms(child.childCount)
        : l10n.countParticipants(child.memberCount);
    final caption = child.isSpace && !canEnter
        ? (onTrail ? l10n.spaceAlreadyOpen : l10n.spaceTooDeep)
        : null;
    final tappable = onTap != null;
    return Semantics(
      button: tappable,
      label: '$name, $subtitle${joined == null ? ', ${l10n.join}' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.removeFromSpace): ?onRemove,
      },
      child: InkWell(
        onTap: onTap,
        onLongPress: onRemove,
        onSecondaryTap: onRemove,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 66),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 12,
              children: [
                Avatar(
                  mxContent: child.avatar ?? joined?.avatar,
                  name: name,
                  size: 46,
                  colorSeed: child.roomId,
                  client: client,
                  borderRadius: child.isSpace
                      ? BorderRadius.circular(14)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        caption ?? subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.mut, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (joined != null) UnreadBubble(room: joined),
                if (joined == null)
                  Semantics(
                    button: true,
                    label: '${l10n.join}, $name',
                    excludeSemantics: true,
                    onTap: onJoin,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onJoin,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          minWidth: 44,
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tokens.accs,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              l10n.join,
                              style: TextStyle(
                                color: tokens.acc,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (child.isSpace && canEnter)
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: tokens.mut,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
