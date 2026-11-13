// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:fluffychat/widgets/layouts/app_nav_rail.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/own_avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final String location;

  final Stream<Object?>? accountSwitched;
  final Stream<Object?>? activeClientChanged;
  final VoidCallback? onFirstShown;

  final Widget Function(BuildContext context, AppTab tab) leftColumn;
  final Widget Function(double size) profileAvatar;
  final int accountCount;

  const AppShell({
    required this.navigationShell,
    required this.location,
    required this.leftColumn,
    this.profileAvatar = _ownAvatar,
    this.accountCount = 1,
    this.accountSwitched,
    this.activeClientChanged,
    this.onFirstShown,
    super.key,
  });

  static Widget _ownAvatar(double size) => OwnAvatar(size: size);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<Object?>? _accountSubscription;
  StreamSubscription<Object?>? _clientSubscription;

  AppTab get _selected => AppTab.values[widget.navigationShell.currentIndex];

  void _select(AppTab tab) => widget.navigationShell.goBranch(
    tab.index,
    initialLocation: tab == _selected,
  );

  @override
  void initState() {
    super.initState();
    _accountSubscription =
        (widget.accountSwitched ?? Matrix.of(context).onAccountSwitched).listen(
          (_) => _resetTabs(keepCurrent: false),
        );
    _clientSubscription =
        (widget.activeClientChanged ?? Matrix.of(context).onActiveClientChanged)
            .listen((_) => _resetTabs(keepCurrent: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstShown?.call();
    });
  }

  bool _resetting = false;
  bool _keepCurrentTab = true;

  // go_router only applies the last navigation of a frame, hence one frame
  // per tab, hidden meanwhile. A destination switch navigates right after
  // switching, so wait for that navigation before reading the current tab.
  Future<void> _resetTabs({required bool keepCurrent}) async {
    _keepCurrentTab = _keepCurrentTab && keepCurrent;
    if (_resetting) return;
    setState(() => _resetting = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
    if (AppTab.forPath(path) != null) {
      final current = widget.navigationShell.currentIndex;
      final tabs = AppTab.visible(callsEnabled: AppSettings.callsEnabled.value);
      for (final tab in tabs) {
        if (tab.index == current) continue;
        widget.navigationShell.goBranch(tab.index, initialLocation: true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      widget.navigationShell.goBranch(
        current,
        initialLocation: !_keepCurrentTab,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    _keepCurrentTab = true;
    setState(() => _resetting = false);
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    _clientSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final mode = ShellMode.forWidth(mq.size.width);
    final tabs = AppTab.visible(callsEnabled: AppSettings.callsEnabled.value);
    final selected = _selected;
    return PopScope(
      canPop: selected == AppTab.chats || !AppTab.isRoot(widget.location),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(AppTab.chats);
      },
      child: ExcludeSemantics(
        excluding: _resetting,
        child: IgnorePointer(
          ignoring: _resetting,
          child: Opacity(
            opacity: _resetting ? 0 : 1,
            child: mode == ShellMode.mobile
                ? _MobileShell(
                    navigationShell: widget.navigationShell,
                    showBar:
                        AppTab.isRoot(widget.location) &&
                        mq.viewInsets.bottom == 0,
                    bar: AppBottomBar(
                      tabs: tabs,
                      selected: _selected,
                      onSelect: _select,
                      profileAvatar: widget.profileAvatar(25),
                    ),
                  )
                : TwoColumnLayout(
                    rail: mode.hasRail
                        ? AppNavRail(
                            tabs: tabs,
                            selected: _selected,
                            onSelect: _select,
                            profileAvatar: widget.profileAvatar(42),
                            accountCount: widget.accountCount,
                          )
                        : null,
                    mainView: _LeftColumns(
                      selected: _selected,
                      builder: widget.leftColumn,
                      header: mode == ShellMode.twoPane
                          ? AppTabStrip(
                              tabs: tabs,
                              selected: _selected,
                              onSelect: _select,
                              profileAvatar: widget.profileAvatar(26),
                            )
                          : null,
                    ),
                    sideView: widget.navigationShell,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final bool showBar;
  final AppBottomBar bar;

  const _MobileShell({
    required this.navigationShell,
    required this.showBar,
    required this.bar,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = AppBottomBar.occupiedHeight(context);
    final duration = mq.disableAnimations
        ? Duration.zero
        : FluffyThemes.animationDuration;
    return Stack(
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
        Positioned(
          left: 0,
          right: 0,
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
