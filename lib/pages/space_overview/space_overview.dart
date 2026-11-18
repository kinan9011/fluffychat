// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/space_overview/space_overview_view.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/links/matrix_link_policy.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/retention/default_retention.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/route_path.dart';
import 'package:fluffychat/utils/spaces/community_model.dart';
import 'package:fluffychat/utils/spaces/space_hierarchy.dart';
import 'package:fluffychat/utils/spaces/space_trail.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum SpaceOverviewTab { joined, suggested }

class SpaceOverview extends StatefulWidget {
  final String spaceId;
  final SpaceTrail trail;

  /// What the parent overview knew about this space, shown while the space
  /// is not joined and its own state is not available.
  final HierarchyChild? preview;

  const SpaceOverview({
    required this.spaceId,
    this.trail = const SpaceTrail(),
    this.preview,
    super.key,
  });

  @override
  SpaceOverviewController createState() => SpaceOverviewController();
}

class SpaceOverviewController extends State<SpaceOverview> {
  var accumulator = HierarchyAccumulator();
  String? nextBatch;
  var loading = false;
  var failed = false;
  var tab = SpaceOverviewTab.joined;

  var _generation = 0;
  StreamSubscription<SyncUpdate>? _childStateSub;
  StreamSubscription<Client>? _accountSub;
  StreamSubscription<SyncUpdate>? _pushRulesSub;

  Client get _client => Matrix.of(context).client;

  Client get accountClient => _client;

  SpaceTrail get path => widget.trail.enter(widget.spaceId);

  /// The space as a room of this account, null when it is not joined.
  Room? get space {
    final room = _client.getRoomById(widget.spaceId);
    return room != null && room.membership == Membership.join && room.isSpace
        ? room
        : null;
  }

  Room? joinedRoom(String roomId) {
    final room = _client.getRoomById(roomId);
    return room != null && room.membership == Membership.join ? room : null;
  }

  bool get canLoadMore =>
      !accumulator.exhausted && (accumulator.pages == 0 || nextBatch != null);

  String get title {
    final room = space;
    final name =
        room?.getLocalizedDisplayname(MatrixLocals(L10n.of(context))) ??
        widget.preview?.name;
    return name == null || name.isEmpty
        ? L10n.of(context).spaceOverview
        : safeDisplayText(name);
  }

  String? get topic {
    final text = space?.topic;
    if (text != null && text.isNotEmpty) {
      return safeDisplayText(text, maxGraphemes: HierarchyParser.maxTopicChars);
    }
    return widget.preview?.topic;
  }

  int? get memberCount =>
      space?.summary.mJoinedMemberCount ?? widget.preview?.memberCount;

  bool get isAdmin => space?.canChangeStateEvent(EventTypes.SpaceChild) == true;

  Set<String> get _suggestedIds {
    final room = space;
    if (room == null) return const {};
    return {
      for (final child in room.spaceChildren)
        if (child.suggested == true && child.roomId != null) child.roomId!,
    };
  }

  List<HierarchyChild> get joinedChildren => [
    for (final child in accumulator.children)
      if (joinedRoom(child.roomId) != null) child,
  ];

  List<HierarchyChild> get suggestedChildren => [
    for (final child in accumulator.children)
      if (joinedRoom(child.roomId) == null &&
          _suggestedIds.contains(child.roomId))
        child,
  ];

  List<HierarchyChild> get otherChildren => [
    for (final child in accumulator.children)
      if (joinedRoom(child.roomId) == null &&
          !_suggestedIds.contains(child.roomId))
        child,
  ];

  /// The announcements room of this space, if it has one (only read from the
  /// power levels of rooms this account is in).
  AnnouncementsRoom? get announcements {
    if (space == null) return null;
    return CommunityModel.find([
      for (final child in accumulator.children)
        ChildPowerLevels(
          roomId: child.roomId,
          joined: joinedRoom(child.roomId) != null,
          isSpace: child.isSpace,
          powerLevels: joinedRoom(
            child.roomId,
          )?.getState(EventTypes.RoomPowerLevels)?.content,
          encrypted: joinedRoom(child.roomId)?.encrypted ?? false,
        ),
    ], ownUserId: _client.userID ?? '');
  }

  Room? get announcementsRoom {
    final found = announcements;
    return found == null ? null : joinedRoom(found.roomId);
  }

  /// The last message of the announcements room as plain text; nothing when
  /// the retention timer of that room hides it.
  String? announcementsPreview(Room room) {
    final event = room.lastEvent;
    if (event == null || event.type != EventTypes.Message) return null;
    if (RetentionPolicy.forRoom(room)?.hides(event, DateTime.now()) == true) {
      return null;
    }
    final text = safeDisplayText(event.body, maxGraphemes: 140);
    return text.isEmpty ? null : text;
  }

  /// A matrix.to link to the space, with the own server as the way in.
  String? get inviteLink {
    final room = space;
    final host = _client.userID?.domain;
    if (room == null || host == null) return null;
    return MatrixLinkPolicy.inviteLink(
      alias: room.canonicalAlias,
      roomId: room.id,
      via: host,
    );
  }

  Future<void> shareInviteLink() async {
    final link = inviteLink;
    if (link == null) return;
    await FluffyShare.share(link, context);
  }

  /// A space holds no messages, so the choice is the one of the announcements
  /// room, which is what members are notified about.
  PushRuleState get notificationState =>
      _chosenNotifications ??
      announcementsRoom?.pushRuleState ??
      PushRuleState.notify;

  PushRuleState? _chosenNotifications;

  Future<void> chooseNotifications() async {
    final l10n = L10n.of(context);
    final roomId = announcementsRoom?.id;
    if (roomId == null) return;
    final choice = await showModalActionPopup<PushRuleState>(
      context: context,
      title: l10n.notifications,
      message: l10n.communityNotificationsNote,
      cancelLabel: l10n.cancel,
      actions: [
        AdaptiveModalAction(
          label: l10n.communityNotificationsAll,
          value: PushRuleState.notify,
          isDefaultAction: notificationState == PushRuleState.notify,
        ),
        AdaptiveModalAction(
          label: l10n.communityNotificationsMentions,
          value: PushRuleState.mentionsOnly,
          isDefaultAction: notificationState == PushRuleState.mentionsOnly,
        ),
        AdaptiveModalAction(
          label: l10n.muted,
          value: PushRuleState.dontNotify,
          isDefaultAction: notificationState == PushRuleState.dontNotify,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    final room = joinedRoom(roomId);
    if (room == null) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room.setPushRuleState(choice),
    );
    if (result.error != null || !mounted) return;
    setState(() => _chosenNotifications = choice);
  }

  /// Creates a group in this space where only moderators and admins can post
  /// and adds it as a suggested child. Matrix has no channels: the dialog
  /// says that before anything is created.
  Future<void> addAnnouncementsRoom() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final room = space;
    if (room == null || !isAdmin) return;
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: l10n.communityAddAnnouncements,
      message: l10n.communityNoChannelsNote,
      okLabel: l10n.communityAddAnnouncements,
      cancelLabel: l10n.cancel,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final client = matrix.client;
        final roomId = await client.createGroupChat(
          groupName: l10n.communityAnnouncements,
          powerLevelContentOverride: {
            'events_default': CommunityModel.moderatorLevel,
          },
          initialState: [
            ...await DefaultRetention.initialStateFor(
              matrix.serverCapabilities,
              client,
            ),
            StateEvent(
              type: EventTypes.RoomJoinRules,
              content: {
                'join_rule': 'restricted',
                'allow': [
                  {'type': 'm.room_membership', 'room_id': room.id},
                ],
              },
            ),
          ],
        );
        await room.postLoad();
        await room.setSpaceChild(roomId, suggested: true, order: '0');
      },
    );
    if (result.error == null && mounted) unawaited(load(reset: true));
  }

  @override
  void initState() {
    super.initState();
    unawaited(load(reset: true));
    _accountSub = Matrix.of(context).onActiveClientChanged.listen((_) {
      if (mounted) context.go('/rooms');
    });
    _pushRulesSub = Matrix.of(context).client.onSync.stream
        .where(
          (sync) =>
              sync.accountData?.any(
                (event) => event.type == EventTypes.PushRules,
              ) ??
              false,
        )
        .listen((_) {
          if (mounted) setState(() => _chosenNotifications = null);
        });
    _childStateSub = Matrix.of(context).client.onSync.stream
        .where(
          (sync) =>
              sync.rooms?.join?[widget.spaceId]?.timeline?.events?.any(
                (event) => event.type == EventTypes.SpaceChild,
              ) ??
              false,
        )
        .listen((_) => unawaited(load(reset: true)));
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_pushRulesSub?.cancel());
    unawaited(_childStateSub?.cancel());
    unawaited(_accountSub?.cancel());
    super.dispose();
  }

  static const _maxParallelLevelRequests = 4;

  /// Workaround: the SDK keeps only important state of a room in memory
  /// (`Room.partial`) and `m.room.power_levels` is not important. Loading the
  /// whole room for it would read every member too, so this asks the server
  /// for that one state event, a few rooms at a time; a room that holds its
  /// power levels in memory is not asked again.
  Future<void> _loadPowerLevels(Iterable<String> roomIds) async {
    final pending = roomIds.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        await _loadPowerLevelsOf(pending[next++]);
      }
    }

    await Future.wait([
      for (
        var i = 0;
        i < math.min(_maxParallelLevelRequests, pending.length);
        i++
      )
        worker(),
    ]);
  }

  Future<void> _loadPowerLevelsOf(String roomId) async {
    final known = joinedRoom(roomId);
    if (known == null) return;
    if (known.getState(EventTypes.RoomPowerLevels) != null) return;
    try {
      final content = await known.client.getRoomStateWithKey(
        roomId,
        EventTypes.RoomPowerLevels,
        '',
      );
      final room = joinedRoom(roomId);
      if (room == null) return;
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomPowerLevels,
          content: content,
          senderId: room.client.userID ?? '',
          stateKey: '',
        ),
      );
    } catch (_) {
      Logs().w('[Spaces] power levels not loaded');
    }
  }

  /// Loads the next page. With [reset] it starts over: a change of the
  /// children while paging would otherwise continue with a stale token.
  Future<void> load({bool reset = false}) async {
    if (reset) {
      _generation++;
      accumulator = HierarchyAccumulator();
      nextBatch = null;
    } else if (loading || !canLoadMore) {
      return;
    }
    final generation = _generation;
    final client = _client;
    final spaceId = widget.spaceId;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final json = await fetchHierarchyPage(client, spaceId, from: nextBatch);
      if (!mounted || generation != _generation) return;
      final page = HierarchyParser.parse(
        json,
        rootId: spaceId,
        seen: accumulator.seen,
      );
      await _loadPowerLevels([
        for (final child in page.children)
          if (!child.isSpace) child.roomId,
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        accumulator.add(page);
        nextBatch = page.nextBatch;
        loading = false;
      });
    } catch (_) {
      Logs().w('[Spaces] hierarchy failed');
      if (!mounted || generation != _generation) return;
      setState(() {
        loading = false;
        failed = true;
      });
    }
  }

  void selectTab(SpaceOverviewTab selected) => setState(() => tab = selected);

  bool canEnter(HierarchyChild child) => path.canEnter(child.roomId);

  bool onTrail(HierarchyChild child) => path.ids.contains(child.roomId);

  void enter(HierarchyChild child) {
    if (!child.isSpace || !canEnter(child)) return;
    final trail = path.encode();
    unawaited(
      context.push(
        routePath(['rooms', 'space', child.roomId], query: {'trail': ?trail}),
        extra: child,
      ),
    );
  }

  void openRoom(Room room) {
    if (!isMatrixRoomId(room.id)) return;
    if (room.isSpace) {
      final trail = path.encode();
      if (!path.canEnter(room.id)) return;
      unawaited(
        context.push(
          routePath(['rooms', 'space', room.id], query: {'trail': ?trail}),
        ),
      );
      return;
    }
    context.go(routePath(['rooms', room.id]));
  }

  static String? _serverOf(String id) {
    final colon = id.indexOf(':');
    return colon < 0 ? null : id.substring(colon + 1);
  }

  /// Joins [child] after the user tapped its button. The servers to join
  /// through come from the state of the space this account is in, never from
  /// the answer of the hierarchy.
  Future<void> join(HierarchyChild child) async {
    final client = _client;
    final fromState = MatrixLinkPolicy.safeVia(
      space?.spaceChildren
              .where((entry) => entry.roomId == child.roomId)
              .expand((entry) => entry.via) ??
          const [],
    );
    final via = fromState.isNotEmpty
        ? fromState
        : MatrixLinkPolicy.safeVia([
            _serverOf(child.roomId),
            _serverOf(widget.spaceId),
          ]);
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final waitForRoom = client.waitForRoomInSync(child.roomId, join: true);
        await client.joinRoom(child.roomId, via: via.isEmpty ? null : via);
        await waitForRoom;
      },
    );
    if (result.error != null || !mounted) return;
    final room = joinedRoom(child.roomId);
    if (room != null) openRoom(room);
  }

  /// Detaches [child] from this space. The room itself is not touched.
  Future<void> removeFromSpace(HierarchyChild child) async {
    final l10n = L10n.of(context);
    final room = space;
    if (room == null || !isAdmin) return;
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: l10n.removeFromSpace,
      message: l10n.removeFromSpaceDescription,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room.removeSpaceChild(child.roomId),
    );
    if (result.error == null && mounted) unawaited(load(reset: true));
  }

  void invite() => context.go(routePath(['rooms', widget.spaceId, 'invite']));

  void addRoom() => context.go(
    Uri(
      path: '/rooms/newgroup',
      queryParameters: {'space_id': widget.spaceId},
    ).toString(),
  );

  Future<void> openSettings() async {
    await space?.postLoad();
    if (!mounted) return;
    unawaited(context.push(routePath(['rooms', widget.spaceId, 'details'])));
  }

  Future<void> leave() async {
    final l10n = L10n.of(context);
    final room = space;
    if (room == null) return;
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: l10n.areYouSure,
      message: l10n.archiveRoomDescription,
      okLabel: l10n.leave,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (result.error != null || !mounted) return;
    close();
  }

  void close() => context.canPop() ? context.pop() : context.go('/rooms');

  @override
  Widget build(BuildContext context) => SpaceOverviewView(this);
}
