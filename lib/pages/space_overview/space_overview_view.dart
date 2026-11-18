// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/space_overview/community_widgets.dart';
import 'package:fluffychat/pages/space_overview/space_overview.dart';
import 'package:fluffychat/pages/space_overview/space_overview_widgets.dart';
import 'package:fluffychat/utils/spaces/space_hierarchy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SpaceOverviewView extends StatelessWidget {
  final SpaceOverviewController controller;

  const SpaceOverviewView(this.controller, {super.key});

  static const listKey = ValueKey('space_overview_list');
  static const retryKey = ValueKey('space_overview_retry');
  static const loadMoreKey = ValueKey('space_overview_load_more');
  static const _otherRoomsLabel = Object();

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final space = c.space;
    final client = c.accountClient;
    final joined = c.joinedChildren;
    final suggested = c.suggestedChildren;
    final others = c.otherChildren;
    final count = c.memberCount;
    final shown = space == null
        ? [...c.accumulator.children]
        : c.tab == SpaceOverviewTab.joined
        ? joined
        : suggested;
    final announcements = c.announcements;
    final announcementsRoom = c.announcementsRoom;
    final community = announcements != null && announcementsRoom != null;
    final tabs = space != null && !community;
    final groups = [
      ...joined.where((child) => child.roomId != announcements?.roomId),
      ...suggested,
      ...others,
    ];
    final primary = community ? groups : shown;
    final secondary = !community && tabs && c.tab == SpaceOverviewTab.suggested
        ? others
        : const <HierarchyChild>[];
    final menu = space == null
        ? null
        : PopupMenuButton<void>(
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            icon: Icon(Icons.more_vert_rounded, color: tokens.mut),
            itemBuilder: (context) => [
              if (c.isAdmin && !community)
                PopupMenuItem(
                  onTap: c.addAnnouncementsRoom,
                  child: Text(l10n.communityAddAnnouncements),
                ),
              PopupMenuItem(onTap: c.leave, child: Text(l10n.leave)),
            ],
          );
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSettingsLayout.maxWidth,
              ),
              child: ListView(
                key: listKey,
                padding: const EdgeInsetsDirectional.only(bottom: 32),
                children: [
                  if (community) ...[
                    CommunityBanner(
                      spaceId: c.widget.spaceId,
                      title: c.title,
                      avatar: space?.avatar ?? c.widget.preview?.avatar,
                      client: client,
                      onBack: c.close,
                      trailing: menu,
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 18,
                        top: 8,
                        end: 16,
                        bottom: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 3,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              c.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.fg,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          Text(
                            count == null
                                ? l10n.spaceOverview
                                : l10n.communityMembersCount(count),
                            style: TextStyle(color: tokens.mut, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 16,
                        end: 16,
                        bottom: 14,
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          if (c.inviteLink != null)
                            Expanded(
                              child: SpaceActionButton(
                                icon: Icons.link_rounded,
                                label: l10n.communityInviteLink,
                                primary: true,
                                onTap: c.shareInviteLink,
                              ),
                            ),
                          Expanded(
                            child: SpaceActionButton(
                              icon: switch (c.notificationState) {
                                PushRuleState.notify =>
                                  Icons.notifications_on_outlined,
                                PushRuleState.mentionsOnly =>
                                  Icons.alternate_email_rounded,
                                PushRuleState.dontNotify =>
                                  Icons.notifications_off_outlined,
                              },
                              label: switch (c.notificationState) {
                                PushRuleState.notify =>
                                  l10n.communityNotificationsAll,
                                PushRuleState.mentionsOnly =>
                                  l10n.communityNotificationsMentions,
                                PushRuleState.dontNotify => l10n.muted,
                              },
                              semanticsLabel: l10n.notifications,
                              onTap: c.chooseNotifications,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnnouncementsCard(
                      title: l10n.communityAnnouncements,
                      preview: c.announcementsPreview(announcementsRoom),
                      time: announcementsRoom.lastEvent?.originServerTs,
                      userCanPost: announcements.userCanPost,
                      onTap: () => c.openRoom(announcementsRoom),
                    ),
                    if (c.isAdmin)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 16,
                          end: 16,
                          bottom: 14,
                        ),
                        child: Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: SpaceActionButton(
                                icon: Icons.add_rounded,
                                label: l10n.spaceAddRoom,
                                onTap: c.addRoom,
                              ),
                            ),
                            SizedBox.square(
                              dimension: 44,
                              child: Semantics(
                                button: true,
                                label: l10n.settings,
                                excludeSemantics: true,
                                onTap: c.openSettings,
                                child: Material(
                                  color: tokens.surf2,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: c.openSettings,
                                    child: Icon(
                                      Icons.settings_outlined,
                                      size: 20,
                                      color: tokens.fg,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 32,
                        end: 16,
                        bottom: 6,
                      ),
                      child: Text(
                        l10n.communityGroups,
                        style: TextStyle(
                          color: tokens.mut,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.48,
                        ),
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 4,
                        top: 4,
                        end: 4,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            onPressed: c.close,
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: tokens.fg,
                            ),
                          ),
                          const Spacer(),
                          ?menu,
                        ],
                      ),
                    ),
                    SpaceHeader(
                      title: c.title,
                      spaceId: c.widget.spaceId,
                      avatar: space?.avatar ?? c.widget.preview?.avatar,
                      subtitle: count == null
                          ? l10n.spaceOverview
                          : l10n.spaceMembersCount(count),
                      topic: c.topic,
                      client: client,
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 16,
                        end: 16,
                        bottom: 14,
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          if (space != null)
                            Expanded(
                              child: SpaceActionButton(
                                icon: Icons.person_add_alt_rounded,
                                label: l10n.invite,
                                primary: true,
                                onTap: c.invite,
                              ),
                            ),
                          if (c.isAdmin)
                            Expanded(
                              child: SpaceActionButton(
                                icon: Icons.add_rounded,
                                label: l10n.spaceAddRoom,
                                onTap: c.addRoom,
                              ),
                            ),
                          if (space != null)
                            SizedBox.square(
                              dimension: 44,
                              child: Semantics(
                                button: true,
                                label: l10n.settings,
                                excludeSemantics: true,
                                onTap: c.openSettings,
                                child: Material(
                                  color: tokens.surf2,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: c.openSettings,
                                    child: Icon(
                                      Icons.settings_outlined,
                                      size: 20,
                                      color: tokens.fg,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (tabs)
                    SpaceTabsRow(
                      joinedSelected: c.tab == SpaceOverviewTab.joined,
                      joinedCount: joined.length,
                      suggestedCount: suggested.length,
                      onJoined: () => c.selectTab(SpaceOverviewTab.joined),
                      onSuggested: () =>
                          c.selectTab(SpaceOverviewTab.suggested),
                    ),
                  for (final item in [
                    ...primary,
                    if (secondary.isNotEmpty) _otherRoomsLabel,
                    ...secondary,
                  ])
                    if (item is HierarchyChild)
                      HierarchyRow(
                        key: ValueKey('overview_${item.roomId}'),
                        child: item,
                        client: client,
                        joined: c.joinedRoom(item.roomId),
                        canEnter: c.canEnter(item),
                        onTrail: c.onTrail(item),
                        onTap: _tapOf(c, item),
                        onJoin: () => c.join(item),
                        onRemove: c.isAdmin
                            ? () => c.removeFromSpace(item)
                            : null,
                      )
                    else
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 32,
                          top: 16,
                          end: 16,
                          bottom: 6,
                        ),
                        child: Text(
                          l10n.spaceOtherRooms,
                          style: TextStyle(
                            color: tokens.mut,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.48,
                          ),
                        ),
                      ),
                  if (c.loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    ),
                  if (c.failed)
                    Semantics(
                      button: true,
                      label: l10n.spaceLoadFailed,
                      excludeSemantics: true,
                      onTap: () => c.load(reset: true),
                      child: InkWell(
                        key: retryKey,
                        onTap: () => c.load(reset: true),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              spacing: 10,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  color: tokens.red,
                                  size: 20,
                                ),
                                Expanded(
                                  child: Text(
                                    l10n.spaceLoadFailed,
                                    style: TextStyle(color: tokens.fg),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (c.accumulator.capped)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 16,
                        top: 12,
                        end: 16,
                      ),
                      child: Text(
                        l10n.spaceListCapped(c.accumulator.children.length),
                        style: TextStyle(color: tokens.mut, fontSize: 12.5),
                      ),
                    ),
                  if (c.canLoadMore && !c.loading && !c.failed)
                    Center(
                      child: TextButton(
                        key: loadMoreKey,
                        onPressed: c.load,
                        child: Text(l10n.loadMore),
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

  static VoidCallback? _tapOf(SpaceOverviewController c, HierarchyChild child) {
    final room = c.joinedRoom(child.roomId);
    if (room != null) return () => c.openRoom(room);
    if (child.isSpace && c.canEnter(child)) return () => c.enter(child);
    return null;
  }
}
