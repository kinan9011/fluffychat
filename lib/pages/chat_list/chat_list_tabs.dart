// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat_list/folder_filter.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

@immutable
class ChatListTabData {
  final ChatListScope scope;
  final String label;
  final int count;
  final SpaceTab? space;

  const ChatListTabData({
    required this.scope,
    required this.label,
    required this.count,
    this.space,
  });
}

List<ChatListTabData> chatListTabData(
  List<ChatListTabItem> items, {
  required L10n l10n,
  required SpaceNavigationMode mode,
  required bool showCounts,
  required int Function(ChatListScope) countOf,
}) => [
  for (final item in items)
    ChatListTabData(
      scope: item.scope,
      space: item.space,
      label: switch (item.folder.kind) {
        _ when item.space != null => item.space!.name,
        FolderKind.all =>
          mode == SpaceNavigationMode.tabs ? l10n.allChats : l10n.all,
        FolderKind.unread => l10n.unread,
        FolderKind.personal => l10n.personal,
        FolderKind.groups => l10n.groups,
        FolderKind.tag => item.folder.value!.replaceFirst('u.', ''),
        FolderKind.user => '',
      },
      count:
          showCounts &&
              (item.space != null ||
                  item.folder.kind != FolderKind.all ||
                  mode == SpaceNavigationMode.switcher)
          ? countOf(item.scope)
          : 0,
    ),
];

class ChatListTabBar extends StatefulWidget {
  final List<ChatListTabData> tabs;
  final ChatListScope selected;
  final ValueChanged<ChatListScope> onSelect;
  final ValueChanged<ChatListTabData>? onLongPress;
  final Client? client;

  const ChatListTabBar({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.onLongPress,
    this.client,
    super.key,
  });

  @override
  State<ChatListTabBar> createState() => _ChatListTabBarState();
}

class _ChatListTabBarState extends State<ChatListTabBar> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(ChatListTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _scrollToSelected();
  }

  void _scrollToSelected() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _selectedKey.currentContext;
    if (context == null || !context.mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
    );
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 12, end: 12, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: tokens.surf2,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 2,
          children: [
            for (final tab in widget.tabs)
              _TabPill(
                key: tab.scope == widget.selected ? _selectedKey : null,
                tab: tab,
                client: widget.client,
                selected: tab.scope == widget.selected,
                onTap: () => widget.onSelect(tab.scope),
                onLongPress: widget.onLongPress == null
                    ? null
                    : () => widget.onLongPress!(tab),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final ChatListTabData tab;
  final Client? client;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _TabPill({
    required this.tab,
    required this.client,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final color = selected ? tokens.acc : tokens.fg;
    final count = tab.count;
    final space = tab.space;
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? l10n.tabUnreadSemantics(tab.label, count) : tab.label,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(23),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? tokens.accs : Colors.transparent,
                borderRadius: BorderRadius.circular(19),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 38),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      if (space != null)
                        Avatar(
                          client: client,
                          mxContent: space.avatar,
                          name: space.name,
                          colorSeed: space.spaceId,
                          size: 20,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                      if (count > 0) _CountBadge(count: count),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTokens.of(context).mbad,
      borderRadius: BorderRadius.circular(10),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}
