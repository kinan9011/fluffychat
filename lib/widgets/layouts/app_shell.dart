// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/chat_list/unread_counts.dart';
import 'package:fluffychat/utils/motion.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:fluffychat/widgets/layouts/app_nav_rail.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/own_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final String location;

  final Stream<Object?>? accountSwitched;
  final Stream<Object?>? activeClientChanged;
  final VoidCallback? onFirstShown;
  final ValueListenable<bool>? callsAvailable;

  final Widget Function(BuildContext context, AppTab tab) leftColumn;
  final Widget Function(double size) profileAvatar;
  final int accountCount;
  final Stream<int>? chatsUnread;

  const AppShell({
    required this.navigationShell,
    required this.location,
    required this.leftColumn,
    this.profileAvatar = _ownAvatar,
    this.accountCount = 1,
    this.chatsUnread,
    this.accountSwitched,
    this.activeClientChanged,
    this.onFirstShown,
    this.callsAvailable,
    super.key,
  });

  static Widget _ownAvatar(double size) => OwnAvatar(size: size);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<Object?>? _accountSubscription;
  StreamSubscription<Object?>? _clientSubscription;
  final ValueNotifier<int> _chatsUnread = ValueNotifier(0);
  StreamSubscription<int>? _unreadSubscription;

  void _watchUnread() {
    _unreadSubscription?.cancel();
    final injected = widget.chatsUnread;
    if (injected != null) {
      _unreadSubscription = injected.listen((count) {
        _chatsUnread.value = count;
      });
      return;
    }
    final client = Matrix.of(context).client;
    _chatsUnread.value = unreadChatCount(client.rooms);
    _unreadSubscription = client.onSync.stream
        .where((sync) => sync.hasRoomUpdate)
        .rateLimit(const Duration(seconds: 1))
        .map((_) => unreadChatCount(client.rooms))
        .listen((count) => _chatsUnread.value = count);
  }

  AppTab get _selected => AppTab.values[widget.navigationShell.currentIndex];

  final Set<int> _stale = {};
  final FocusNode _navFocus = FocusNode(debugLabel: 'shell navigation');
  FocusNode? _returnFocus;

  void _select(AppTab tab) {
    final holdsOldAccount = _stale.remove(tab.index);
    widget.navigationShell.goBranch(
      tab.index,
      initialLocation: holdsOldAccount || tab == _selected,
    );
  }

  void _markAllStale() => _stale
    ..clear()
    ..addAll(AppTab.values.map((tab) => tab.index));

  // A destination that comes with a switch navigates right after it, and the
  // shell only learns about that in the next frame: until then the branch we
  // were on must count as stale too, or it would keep the old account's page.
  Future<void> _markOthersStale() async {
    _markAllStale();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _stale.remove(widget.navigationShell.currentIndex);
  }

  void _onActiveClientChanged() {
    if (widget.chatsUnread == null) _watchUnread();
    unawaited(_markOthersStale());
  }

  Future<void> _onAccountSwitched() async {
    final location = widget.location;
    await _markOthersStale();
    if (!mounted || widget.location != location) return;
    widget.navigationShell.goBranch(
      widget.navigationShell.currentIndex,
      initialLocation: true,
    );
  }

  void _toggleNavigationFocus() {
    if (!_navFocus.hasFocus) {
      _returnFocus = FocusManager.instance.primaryFocus;
      _navFocus.requestFocus();
      return;
    }
    final back = _returnFocus;
    if (back != null && back.context != null) {
      back.requestFocus();
      return;
    }
    FocusManager.instance.primaryFocus?.nextFocus();
  }

  late final Listenable _callsListenable =
      widget.callsAvailable ?? Matrix.of(context).callsAvailability;

  bool get _callsOn {
    final injected = widget.callsAvailable;
    if (injected != null) return injected.value;
    final matrix = Matrix.of(context);
    final active = matrix.activeClientOrNull;
    return active != null && matrix.callsAvailableFor(active);
  }

  void _onCallsAvailabilityChanged() {
    if (!mounted) return;
    setState(() {});
    if (_selected == AppTab.calls && !_callsOn) _select(AppTab.chats);
  }

  @override
  void initState() {
    super.initState();
    _callsListenable.addListener(_onCallsAvailabilityChanged);
    _watchUnread();
    _accountSubscription =
        (widget.accountSwitched ?? Matrix.of(context).onAccountSwitched).listen(
          (_) => _onAccountSwitched(),
        );
    _clientSubscription =
        (widget.activeClientChanged ?? Matrix.of(context).onActiveClientChanged)
            .listen((_) => _onActiveClientChanged());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstShown?.call();
    });
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stale.remove(widget.navigationShell.currentIndex);
  }

  @override
  void dispose() {
    _callsListenable.removeListener(_onCallsAvailabilityChanged);
    _accountSubscription?.cancel();
    _clientSubscription?.cancel();
    _unreadSubscription?.cancel();
    _chatsUnread.dispose();
    _navFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final mode = ShellMode.forSize(mq.size);
    final tabs = AppTab.visible(callsEnabled: _callsOn);
    final selected = _selected;
    return PopScope(
      canPop: selected == AppTab.chats || !AppTab.isRoot(widget.location),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(AppTab.chats);
      },
      child: Shortcuts(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.f6):
              const _FocusNavigationIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyK,
            control: !PlatformInfos.usesCommandKey,
            meta: PlatformInfos.usesCommandKey,
          ): const _QuickSwitcherIntent(),
        },
        child: Actions(
          actions: {
            _FocusNavigationIntent: CallbackAction<_FocusNavigationIntent>(
              onInvoke: (_) {
                _toggleNavigationFocus();
                return null;
              },
            ),
            _QuickSwitcherIntent: CallbackAction<_QuickSwitcherIntent>(
              onInvoke: (_) {
                context.go('/rooms/search');
                return null;
              },
            ),
          },
          child: mode == ShellMode.mobile
              ? _MobileShell(
                  navigationShell: widget.navigationShell,
                  showBar:
                      AppTab.isRoot(widget.location) &&
                      mq.viewInsets.bottom == 0,
                  bar: _ChatsUnread(
                    count: _chatsUnread,
                    builder: (badge) => AppBottomBar(
                      tabs: tabs,
                      selected: selected,
                      onSelect: _select,
                      profileAvatar: widget.profileAvatar(25),
                      chatsBadge: badge,
                      selectedFocus: _navFocus,
                    ),
                  ),
                )
              : TwoColumnLayout(
                  rail: mode.hasRail
                      ? _ChatsUnread(
                          count: _chatsUnread,
                          builder: (badge) => AppNavRail(
                            tabs: tabs,
                            selected: selected,
                            onSelect: _select,
                            profileAvatar: widget.profileAvatar(42),
                            accountCount: widget.accountCount,
                            chatsBadge: badge,
                            selectedFocus: _navFocus,
                          ),
                        )
                      : null,
                  mainView: _LeftColumns(
                    selected: selected,
                    builder: widget.leftColumn,
                    header: mode == ShellMode.twoPane
                        ? _ChatsUnread(
                            count: _chatsUnread,
                            builder: (badge) => AppTabStrip(
                              tabs: tabs,
                              selected: selected,
                              onSelect: _select,
                              profileAvatar: widget.profileAvatar(26),
                              chatsBadge: badge,
                              selectedFocus: _navFocus,
                            ),
                          )
                        : null,
                  ),
                  sideView: widget.navigationShell,
                ),
        ),
      ),
    );
  }
}

class _FocusNavigationIntent extends Intent {
  const _FocusNavigationIntent();
}

class _QuickSwitcherIntent extends Intent {
  const _QuickSwitcherIntent();
}

/// Only the widgets that show the badge rebuild when the count changes.
class _ChatsUnread extends StatelessWidget {
  final ValueNotifier<int> count;
  final Widget Function(int badge) builder;

  const _ChatsUnread({required this.count, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: count,
    builder: (context, badge, _) => builder(badge),
  );
}

class _MobileShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final bool showBar;
  final Widget bar;

  const _MobileShell({
    required this.navigationShell,
    required this.showBar,
    required this.bar,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = AppBottomBar.occupiedHeight(context);
    final duration = motionDuration(context, FluffyThemes.animationDuration);
    return BackdropGroup(
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: showBar
                  ? mq.copyWith(
                      padding: mq.padding.copyWith(bottom: inset),
                      viewPadding: mq.viewPadding.copyWith(bottom: inset),
                    )
                  : mq,
              child: navigationShell,
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: ExcludeSemantics(
              excluding: !showBar,
              child: ExcludeFocus(
                excluding: !showBar,
                child: IgnorePointer(
                  ignoring: !showBar,
                  child: AnimatedSlide(
                    duration: duration,
                    curve: FluffyThemes.animationCurve,
                    offset: showBar ? Offset.zero : const Offset(0, 1),
                    child: AnimatedOpacity(
                      duration: duration,
                      opacity: showBar ? 1 : 0,
                      child: bar,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftColumns extends StatefulWidget {
  final AppTab selected;
  final Widget Function(BuildContext, AppTab) builder;
  final Widget? header;

  const _LeftColumns({
    required this.selected,
    required this.builder,
    required this.header,
  });

  @override
  State<_LeftColumns> createState() => _LeftColumnsState();
}

class _LeftColumnsState extends State<_LeftColumns> {
  final Set<AppTab> _visited = {};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.selected);
    return Column(
      children: [
        ?widget.header,
        Expanded(
          child: IndexedStack(
            index: widget.selected.index,
            children: [
              for (final tab in AppTab.values)
                _visited.contains(tab)
                    ? widget.builder(context, tab)
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
