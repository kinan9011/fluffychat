// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_view.dart';
import 'package:fluffychat/pages/chat_list/swipe_action_row.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/utils/chat_list/swipe_actions.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import '../../../utils/account_bundles.dart';
import '../../config/setting_keys.dart';
import '../../widgets/matrix.dart';

enum SpaceTabAction { overview, settings }

class ChatList extends StatefulWidget {
  final String? activeChat;
  final String? activeSpace;

  const ChatList({super.key, required this.activeChat, this.activeSpace});

  @override
  ChatListController createState() => ChatListController();
}

class ChatListController extends State<ChatList>
    with TickerProviderStateMixin, RouteAware {
  late ChatListScope scope;

  String? get activeTag =>
      scope.folder.kind == FolderKind.tag ? scope.folder.value : null;

  String? _overviewSpaceId;

  String? get overviewSpaceId => _overviewSpaceId;

  static final _roomId = RegExp(r'^![^:\s]{1,255}:[^\s]{1,255}$');

  Future<void> openSpaceOverview(String spaceId) async {
    final space = Matrix.of(context).client.getRoomById(spaceId);
    if (space == null || !space.isJoinedSpace) return;
    await space.postLoad();
    if (!mounted) return;
    setState(() {
      _overviewSpaceId = spaceId;
    });
  }

  void closeSpaceOverview() => setState(() {
    _overviewSpaceId = null;
  });

  void selectTab(ChatListScope newScope) {
    setState(() {
      scope = newScope;
    });
    AppSettings.chatFilter.setItem(newScope.folder.storageKey);
  }

  void resetScope() => setState(() => scope = const ChatListScope());

  void closeArchived() => selectTab(scope.copyWith(archived: false));

  final ValueNotifier<String?> openSwipeRow = ValueNotifier(null);

  late final rowActions = ChatRowActions.forChatList(
    context,
    openSwipeRow,
    chatContextAction,
    leaveChat,
  );

  Future<void> spaceTabAction(String spaceId) async {
    final l10n = L10n.of(context);
    final action = await showModalActionPopup<SpaceTabAction>(
      context: context,
      actions: [
        AdaptiveModalAction(
          value: SpaceTabAction.overview,
          label: l10n.spaceOverview,
        ),
        AdaptiveModalAction(
          value: SpaceTabAction.settings,
          label: l10n.settings,
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case SpaceTabAction.overview:
        await openSpaceOverview(spaceId);
      case SpaceTabAction.settings:
        await editSpace(context, spaceId);
      case null:
    }
  }

  void selectSpace(String? spaceId) => setState(
    () => scope = ChatListScope(spaceId: spaceId, folder: scope.folder),
  );

  void openSpaceFromLink(String raw) {
    if (!_roomId.hasMatch(raw)) return;
    final client = Matrix.of(context).client;
    final space = client.getRoomById(raw);
    if (space == null || !space.isJoinedSpace) return;
    final topLevel = SpaceTabsModel.build(
      client.rooms,
      nameOf: (room) => room.id,
    ).tabs.any((tab) => tab.spaceId == raw);
    if (!topLevel) {
      openSpaceOverview(raw);
      return;
    }
    switch (SpaceNavigationMode.fromSetting(
      AppSettings.spaceNavigation.value,
    )) {
      case SpaceNavigationMode.tabs:
        selectTab(ChatListScope(spaceId: raw));
      case SpaceNavigationMode.switcher:
        selectSpace(raw);
    }
  }

  Future<void> onChatTap(Room room) async {
    if (room.membership == Membership.leave) {
      context.go('/rooms/archive/${room.id}');
      return;
    }

    if (room.isJoinedSpace) {
      openSpaceOverview(room.id);
      return;
    }

    context.go('/rooms/${room.id}');
  }

  bool isSearchMode = false;
  Future<QueryPublicRoomsResponse>? publicRoomsResponse;
  String? searchServer;
  Timer? _coolDown;
  SearchUserDirectoryResponse? userSearchResult;
  QueryPublicRoomsResponse? roomSearchResult;

  bool isSearching = false;
  static const String _serverStoreNamespace = 'im.fluffychat.search.server';

  Future<void> setServer() async {
    final matrix = Matrix.of(context);
    final l10n = L10n.of(context);
    final newServer = await showTextInputDialog(
      useRootNavigator: false,
      title: l10n.changeTheHomeserver,
      context: context,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      prefixText: 'https://',
      hintText: matrix.client.homeserver?.host,
      initialText: searchServer,
      keyboardType: TextInputType.url,
      autocorrect: false,
      validator: (server) =>
          server.contains('.') == true ? null : l10n.invalidServerName,
    );
    if (newServer == null) return;
    if (!mounted) return;
    matrix.store.setString(_serverStoreNamespace, newServer);
    setState(() {
      searchServer = newServer;
    });
    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), _search);
  }

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  Future<void> _search() async {
    final client = Matrix.of(context).client;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!isSearching) {
      setState(() {
        isSearching = true;
      });
    }
    SearchUserDirectoryResponse? userSearchResult;
    QueryPublicRoomsResponse? roomSearchResult;
    final searchQuery = searchController.text.trim();
    try {
      roomSearchResult = await client.queryPublicRooms(
        server: searchServer,
        filter: PublicRoomQueryFilter(genericSearchTerm: searchQuery),
        limit: 20,
      );

      if (searchQuery.isValidMatrixIdStrict() &&
          searchQuery.sigil == '#' &&
          roomSearchResult.chunk.any(
                (room) => room.canonicalAlias == searchQuery,
              ) ==
              false) {
        final response = await client.getRoomIdByAlias(searchQuery);
        final roomId = response.roomId;
        if (roomId != null) {
          roomSearchResult.chunk.add(
            PublishedRoomsChunk(
              name: searchQuery,
              guestCanJoin: false,
              numJoinedMembers: 0,
              roomId: roomId,
              worldReadable: false,
              canonicalAlias: searchQuery,
            ),
          );
        }
      }
      userSearchResult = await client.searchUserDirectory(
        searchController.text,
        limit: 20,
      );
    } catch (e, s) {
      Logs().w('Searching has crashed', e, s);
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
    if (!isSearchMode) return;
    setState(() {
      isSearching = false;
      this.roomSearchResult = roomSearchResult;
      this.userSearchResult = userSearchResult;
    });
  }

  void onSearchEnter(String text, {bool globalSearch = true}) {
    if (text.isEmpty) {
      cancelSearch(unfocus: false);
      return;
    }

    setState(() {
      isSearchMode = true;
    });
    _coolDown?.cancel();
    if (globalSearch) {
      _coolDown = Timer(const Duration(milliseconds: 500), _search);
    }
  }

  void startSearch() {
    setState(() {
      isSearchMode = true;
    });
    searchFocusNode.requestFocus();
    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), _search);
  }

  void cancelSearch({bool unfocus = true}) {
    setState(() {
      searchController.clear();
      isSearchMode = false;
      roomSearchResult = userSearchResult = null;
      isSearching = false;
    });
    if (unfocus) searchFocusNode.unfocus();
  }

  BoxConstraints? snappingSheetContainerSize;

  final ScrollController scrollController = ScrollController();
  final ValueNotifier<bool> scrolledToTop = ValueNotifier(true);

  final StreamController<Client> _clientStream = StreamController.broadcast();

  Stream<Client> get clientStream => _clientStream.stream;

  void addAccountAction() => context.go('/settings/addaccount');

  void _onScroll() {
    openSwipeRow.value = null;
    final newScrolledToTop = scrollController.position.pixels <= 0;
    if (newScrolledToTop != scrolledToTop.value) {
      scrolledToTop.value = newScrolledToTop;
    }
  }

  Future<void> editSpace(BuildContext context, String spaceId) async {
    await Matrix.of(context).client.getRoomById(spaceId)?.postLoad();
    if (!context.mounted) return;
    context.push('/rooms/$spaceId/details');
  }

  String? get activeChat => widget.activeChat;

  @override
  void didUpdateWidget(covariant ChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSpace != null &&
        widget.activeSpace != oldWidget.activeSpace) {
      openSpaceFromLink(widget.activeSpace!);
    }
  }

  StreamSubscription<Client>? _activeClientSubscription;

  @override
  void initState() {
    scope = ChatListScope(
      folder: FolderRef.parse(AppSettings.chatFilter.value),
    );

    _activeClientSubscription = Matrix.of(context).onActiveClientChanged.listen(
      (_) => setState(() {
        scope = const ChatListScope();
        _overviewSpaceId = null;
        openSwipeRow.value = null;
      }),
    );

    scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.activeSpace != null) {
        openSpaceFromLink(widget.activeSpace!);
      }
      if (mounted) {
        searchServer = Matrix.of(
          context,
        ).store.getString(_serverStoreNamespace);
      }

      // Workaround for system UI overlay style not applied on app start
      SystemChrome.setSystemUIOverlayStyle(
        Theme.of(context).appBarTheme.systemOverlayStyle!,
      );
    });

    super.initState();
  }

  @override
  void dispose() {
    _activeClientSubscription?.cancel();
    scrollController.removeListener(_onScroll);
    searchController.dispose();
    searchFocusNode.dispose();
    scrollController.dispose();
    scrolledToTop.dispose();
    openSwipeRow.dispose();
    _clientStream.close();
    super.dispose();
  }

  Future<void> leaveChat(Room room) async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: L10n.of(context).archiveRoomDescription,
      okLabel: L10n.of(context).leave,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
    );
    if (confirmed == OkCancelResult.cancel) return;
    if (!mounted) return;
    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  Future<void> chatContextAction(
    Room room,
    BuildContext posContext, [
    Room? space,
  ]) async {
    final overlay =
        Overlay.of(posContext).context.findRenderObject() as RenderBox;

    final button = posContext.findRenderObject() as RenderBox;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(const Offset(0, -65), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + const Offset(-50, 0),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final spacesWithPowerLevels = room.client.rooms
        .where(
          (space) =>
              space.isSpace &&
              space.canChangeStateEvent(EventTypes.SpaceChild) &&
              !space.spaceChildren.any((c) => c.roomId == room.id),
        )
        .toList();

    var action = await showMenu<ChatContextAction>(
      context: posContext,
      position: position,
      items: [
        if (space != null)
          PopupMenuItem(
            value: ChatContextAction.goToSpace,
            child: Row(
              mainAxisSize: .min,
              children: [
                Avatar(
                  mxContent: space.avatar,
                  size: Avatar.defaultSize / 2,
                  name: space.getLocalizedDisplayname(),
                  colorSeed: space.id,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).goToSpace(space.getLocalizedDisplayname()),
                ),
              ],
            ),
          ),
        if (room.membership == Membership.join) ...[
          PopupMenuItem(
            value: ChatContextAction.mute,
            child: Row(
              mainAxisSize: .min,
              children: [
                Icon(
                  room.pushRuleState == PushRuleState.notify
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_off,
                ),
                const SizedBox(width: 12),
                Text(
                  room.pushRuleState == PushRuleState.notify
                      ? L10n.of(context).muteChat
                      : L10n.of(context).unmuteChat,
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: ChatContextAction.markUnread,
            child: Row(
              mainAxisSize: .min,
              children: [
                Icon(
                  room.markedUnread
                      ? Icons.mark_as_unread
                      : Icons.mark_as_unread_outlined,
                ),
                const SizedBox(width: 12),
                Text(
                  room.markedUnread
                      ? L10n.of(context).markAsRead
                      : L10n.of(context).markAsUnread,
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: ChatContextAction.archive,
            child: Row(
              mainAxisSize: .min,
              children: [
                Icon(
                  room.isArchivedChat
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                const SizedBox(width: 12),
                Text(
                  room.isArchivedChat
                      ? L10n.of(context).unarchive
                      : L10n.of(context).archive,
                ),
              ],
            ),
          ),
          if (!room.isLowPriority)
            PopupMenuItem(
              value: ChatContextAction.favorite,
              child: Row(
                mainAxisSize: .min,
                children: [
                  Icon(
                    room.isFavourite ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    room.isFavourite
                        ? L10n.of(context).unpin
                        : L10n.of(context).pin,
                  ),
                ],
              ),
            ),
        ],
        PopupMenuItem(
          value: ChatContextAction.leave,
          child: Row(
            mainAxisSize: .min,
            children: [
              Icon(
                Icons.delete_outlined,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Text(
                room.membership == Membership.invite
                    ? L10n.of(context).delete
                    : L10n.of(context).leave,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
        if (room.membership == Membership.invite)
          PopupMenuItem(
            value: ChatContextAction.block,
            child: Row(
              mainAxisSize: .min,
              children: [
                Icon(
                  Icons.block_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).block,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        if (room.membership == Membership.join)
          PopupMenuItem(
            value: ChatContextAction.showMore,
            child: Row(
              mainAxisSize: .min,
              children: [
                Icon(Icons.adaptive.more_outlined),
                const SizedBox(width: 12),
                Text(L10n.of(context).more),
              ],
            ),
          ),
      ],
    );
    if (!posContext.mounted || !mounted) return;
    if (action == ChatContextAction.showMore) {
      action = await showMenu<ChatContextAction>(
        context: posContext,
        position: position,
        items: [
          if (!room.isFavourite)
            PopupMenuItem(
              value: ChatContextAction.lowPriority,
              child: Row(
                mainAxisSize: .min,
                children: [
                  Icon(
                    room.isLowPriority
                        ? Icons.low_priority
                        : Icons.low_priority_outlined,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    room.isLowPriority
                        ? L10n.of(context).unsetLowPriority
                        : L10n.of(context).setLowPriority,
                  ),
                ],
              ),
            ),
          if (activeTag == null)
            PopupMenuItem(
              value: ChatContextAction.addTag,
              child: Row(
                mainAxisSize: .min,
                children: [
                  Icon(Icons.bookmark_add_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).addTag),
                ],
              ),
            )
          else
            PopupMenuItem(
              value: ChatContextAction.removeTag,
              child: Row(
                mainAxisSize: .min,
                children: [
                  Icon(Icons.bookmark_remove_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).removeTag),
                ],
              ),
            ),
          if (spacesWithPowerLevels.isNotEmpty)
            PopupMenuItem(
              value: ChatContextAction.addToSpace,
              child: Row(
                mainAxisSize: .min,
                children: [
                  const Icon(Icons.group_work_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).addToSpace),
                ],
              ),
            ),
        ],
      );
    }

    if (action == null) return;
    if (!mounted) return;

    switch (action) {
      case ChatContextAction.goToSpace:
        openSpaceOverview(space!.id);
        return;
      case ChatContextAction.favorite:
        await showFutureLoadingDialog(
          context: context,
          future: () => runSwipeAction(
            room.client,
            room.id,
            SwipeAction.pin,
            publicReceipts: AppSettings.sendPublicReadReceipts.value,
          ),
        );
        return;
      case ChatContextAction.archive:
        await showFutureLoadingDialog(
          context: context,
          future: () => room.setArchivedChat(!room.isArchivedChat),
        );
        return;
      case ChatContextAction.markUnread:
        await showFutureLoadingDialog(
          context: context,
          future: () => room.markUnread(!room.markedUnread),
        );
        return;
      case ChatContextAction.mute:
        await showFutureLoadingDialog(
          context: context,
          future: () => room.setPushRuleState(
            room.pushRuleState == PushRuleState.notify
                ? PushRuleState.mentionsOnly
                : PushRuleState.notify,
          ),
        );
        return;
      case ChatContextAction.block:
        final inviteEvent = await room.requestUser(room.client.userID!);
        if (!mounted) return;
        context.go(
          '/settings/security/ignorelist',
          extra: inviteEvent?.senderId,
        );
      case ChatContextAction.leave:
        await leaveChat(room);
        return;
      case ChatContextAction.addToSpace:
        final space = await showModalActionPopup(
          context: context,
          title: L10n.of(context).space,
          actions: spacesWithPowerLevels
              .map(
                (space) => AdaptiveModalAction(
                  value: space,
                  label: space.getLocalizedDisplayname(
                    MatrixLocals(L10n.of(context)),
                  ),
                ),
              )
              .toList(),
        );
        if (space == null) return;
        if (!mounted) return;
        await showFutureLoadingDialog(
          context: context,
          future: () => space.setSpaceChild(room.id),
        );
      case ChatContextAction.lowPriority:
        await showFutureLoadingDialog(
          context: context,
          future: () => room.setLowPriority(!room.isLowPriority),
        );
        return;
      case ChatContextAction.addTag:
        final existingTags = List.of(roomTags.keys);
        existingTags.removeWhere(room.tags.containsKey);
        String? tag;
        if (existingTags.isNotEmpty) {
          tag = await showModalActionPopup<String?>(
            context: context,
            actions: [
              ...existingTags.map((tag) {
                final displayTag = tag.replaceFirst('u.', '');
                return AdaptiveModalAction(
                  label: displayTag,
                  value: displayTag,
                );
              }),
              AdaptiveModalAction(
                label: L10n.of(context).createNewTag,
                value: null,
              ),
            ],
          );
          if (!mounted) return;
        }
        tag ??= await showTextInputDialog(
          context: context,
          title: L10n.of(context).addTag,
          hintText: L10n.of(context).tagName,
        );
        final newTag = tag;
        if (!mounted) return;
        if (newTag == null) return;
        await showFutureLoadingDialog(
          context: context,
          future: () => room.addTag('u.$newTag'),
        );
        return;
      case ChatContextAction.removeTag:
        await showFutureLoadingDialog(
          context: context,
          future: () => room.removeTag(activeTag!),
        );
        return;
      case ChatContextAction.showMore:
        throw ('Should not be handled!');
    }
  }

  Map<String, int> get roomTags {
    final tags = <String, int>{};
    for (final room in Matrix.of(context).client.rooms) {
      for (final tag in room.tags.keys) {
        if (tag.startsWith('u.')) tags[tag] = (tags[tag] ?? 0) + 1;
      }
    }
    return tags;
  }

  Future<void> setStatus() async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final currentPresence = await client.fetchCurrentPresence(client.userID!);
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.setStatus,
      message: l10n.leaveEmptyToClearStatus,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.statusExampleMessage,
      maxLines: 6,
      minLines: 1,
      maxLength: 255,
      initialText: currentPresence.statusMsg,
    );
    if (input == null) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => client.setPresence(
        client.userID!,
        PresencePolicy.fromSettings().statusPresence,
        statusMsg: input,
      ),
    );
  }

  void setActiveClient(Client client) {
    context.go('/rooms');
    setState(() {
      scope = const ChatListScope();
      _overviewSpaceId = null;
      Matrix.of(context).setActiveClient(client);
    });
    _clientStream.add(client);
  }

  void setActiveBundle(String bundle) {
    context.go('/rooms');
    setState(() {
      scope = const ChatListScope();
      _overviewSpaceId = null;
      Matrix.of(context).activeBundle = bundle;
      if (!Matrix.of(
        context,
      ).currentBundle!.any((client) => client == Matrix.of(context).client)) {
        Matrix.of(
          context,
        ).setActiveClient(Matrix.of(context).currentBundle!.first);
      }
    });
  }

  Future<void> editBundlesForAccount(
    String? userId,
    String? activeBundle,
  ) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(
      context,
    ).widget.clients[Matrix.of(context).getClientIndexByMatrixId(userId!)];
    final action = await showModalActionPopup<EditBundleAction>(
      context: context,
      title: L10n.of(context).editBundlesForAccount,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          value: EditBundleAction.addToBundle,
          label: L10n.of(context).addToBundle,
        ),
        if (activeBundle != client.userID)
          AdaptiveModalAction(
            value: EditBundleAction.removeFromBundle,
            label: L10n.of(context).removeFromBundle,
          ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case EditBundleAction.addToBundle:
        if (!mounted) return;
        final bundle = await showTextInputDialog(
          context: context,
          title: l10n.bundleName,
          hintText: l10n.bundleName,
        );
        if (bundle == null || bundle.isEmpty || bundle.isEmpty) return;
        if (!mounted) return;
        await showFutureLoadingDialog(
          context: context,
          future: () => client.setAccountBundle(bundle),
        );
        break;
      case EditBundleAction.removeFromBundle:
        if (!mounted) return;
        await showFutureLoadingDialog(
          context: context,
          future: () => client.removeFromAccountBundle(activeBundle!),
        );
    }
  }

  bool get displayBundles =>
      Matrix.of(context).hasComplexBundles &&
      Matrix.of(context).accountBundles.keys.length > 1;

  String? get secureActiveBundle {
    if (Matrix.of(context).activeBundle == null ||
        !Matrix.of(
          context,
        ).accountBundles.keys.contains(Matrix.of(context).activeBundle)) {
      return Matrix.of(context).accountBundles.keys.first;
    }
    return Matrix.of(context).activeBundle;
  }

  void resetActiveBundle() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {
        Matrix.of(context).activeBundle = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) => ChatListView(this);

  Future<void> dehydrate() => Matrix.of(context).dehydrateAction(context);
}

enum EditBundleAction { addToBundle, removeFromBundle }

enum ChatContextAction {
  goToSpace,
  favorite,
  archive,
  lowPriority,
  addTag,
  removeTag,
  markUnread,
  mute,
  leave,
  addToSpace,
  block,
  showMore,
}
