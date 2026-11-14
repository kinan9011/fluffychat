// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SpaceSwitcherChip extends StatefulWidget {
  final List<SpaceTab> spaces;
  final String? selectedSpaceId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCreateSpace;
  final VoidCallback onExplore;
  final Client? client;

  const SpaceSwitcherChip({
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onCreateSpace,
    required this.onExplore,
    this.client,
    super.key,
  });

  @override
  State<SpaceSwitcherChip> createState() => _SpaceSwitcherChipState();
}

class _SpaceSwitcherChipState extends State<SpaceSwitcherChip> {
  bool _open = false;

  SpaceTab? get _selected => widget.spaces
      .where((space) => space.spaceId == widget.selectedSpaceId)
      .firstOrNull;

  Future<void> _openMenu() async {
    final box = context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = true);
    await showSpaceSwitcherMenu(
      context,
      anchor: rect,
      spaces: widget.spaces,
      selectedSpaceId: widget.selectedSpaceId,
      onSelect: widget.onSelect,
      onCreateSpace: widget.onCreateSpace,
      onExplore: widget.onExplore,
      client: widget.client,
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final selected = _selected;
    final name = selected?.name ?? l10n.allChats;
    return Semantics(
      button: true,
      label: l10n.currentSpaceSemantics(name),
      onTap: _openMenu,
      excludeSemantics: true,
      child: Material(
        color: tokens.surf2,
        shape: StadiumBorder(
          side: BorderSide(
            color: _open ? tokens.acc : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openMenu,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 6,
                end: 10,
                top: 2,
                bottom: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  _SpaceAvatar(
                    space: selected,
                    size: 34,
                    radius: 10,
                    client: widget.client,
                  ),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: tokens.mut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceAvatar extends StatelessWidget {
  final SpaceTab? space;
  final double size;
  final double radius;
  final Client? client;

  const _SpaceAvatar({
    required this.space,
    required this.size,
    required this.radius,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final space = this.space;
    if (space == null) {
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surf2,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Icon(Icons.forum_rounded, size: 20, color: tokens.acc),
        ),
      );
    }
    return Avatar(
      client: client,
      mxContent: space.avatar,
      name: space.name,
      colorSeed: space.spaceId,
      size: size,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}

Future<void> showSpaceSwitcherMenu(
  BuildContext context, {
  required Rect anchor,
  required List<SpaceTab> spaces,
  required String? selectedSpaceId,
  required ValueChanged<String?> onSelect,
  required VoidCallback onCreateSpace,
  required VoidCallback onExplore,
  Client? client,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: L10n.of(context).close,
  barrierColor: AppTokens.overlay(0.18),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 160),
  pageBuilder: (dialogContext, _, _) => _SpaceSwitcherMenu(
    anchor: anchor,
    spaces: spaces,
    selectedSpaceId: selectedSpaceId,
    client: client,
    onSelect: (id) {
      Navigator.of(dialogContext).pop();
      onSelect(id);
    },
    onCreateSpace: () {
      Navigator.of(dialogContext).pop();
      onCreateSpace();
    },
    onExplore: () {
      Navigator.of(dialogContext).pop();
      onExplore();
    },
  ),
);

class _SpaceSwitcherMenu extends StatelessWidget {
  final Rect anchor;
  final List<SpaceTab> spaces;
  final String? selectedSpaceId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCreateSpace;
  final VoidCallback onExplore;
  final Client? client;

  const _SpaceSwitcherMenu({
    required this.anchor,
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onCreateSpace,
    required this.onExplore,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final screen = MediaQuery.sizeOf(context);
    final height = screen.height;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final edge = rtl ? screen.width - anchor.right : anchor.left;
    final start = edge
        .clamp(12.0, math.max(12.0, screen.width - 290 - 12))
        .toDouble();
    return FocusScope(
      autofocus: true,
      child: Stack(
        children: [
          PositionedDirectional(
            start: start,
            top: anchor.bottom + 6,
            child: SizedBox(
              width: 290,
              child: GlassSurface(
                blur: 24,
                shadows: AppElevation.menu,
                borderRadius: BorderRadius.circular(24),
                child: Material(
                  type: MaterialType.transparency,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height * 0.6),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              12,
                              6,
                              12,
                              4,
                            ),
                            child: Text(
                              l10n.switchSpace.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.575,
                                color: tokens.mut,
                              ),
                            ),
                          ),
                          _MenuRow(
                            space: null,
                            label: l10n.allChats,
                            current: selectedSpaceId == null,
                            client: client,
                            onTap: () => onSelect(null),
                          ),
                          for (final space in spaces)
                            _MenuRow(
                              space: space,
                              label: space.name,
                              count: space.unread,
                              current: space.spaceId == selectedSpaceId,
                              client: client,
                              onTap: () => onSelect(space.spaceId),
                            ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: tokens.line,
                          ),
                          _ActionRow(
                            icon: Icons.add_rounded,
                            label: l10n.createNewSpace,
                            onTap: onCreateSpace,
                          ),
                          _ActionRow(
                            icon: Icons.travel_explore_rounded,
                            label: l10n.explorePublicSpaces,
                            onTap: onExplore,
                          ),
                        ],
                      ),
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

class _MenuRow extends StatelessWidget {
  final SpaceTab? space;
  final String label;
  final int count;
  final bool current;
  final Client? client;
  final VoidCallback onTap;

  const _MenuRow({
    required this.space,
    required this.label,
    required this.current,
    required this.client,
    required this.onTap,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: current,
      label: count > 0
          ? L10n.of(context).tabUnreadSemantics(label, count)
          : label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: current ? tokens.accs : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: current,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                spacing: 12,
                children: [
                  _SpaceAvatar(
                    space: space,
                    size: 34,
                    radius: 11,
                    client: client,
                  ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Text(
                      count > 99 ? '99+' : '$count',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.mut,
                      ),
                    ),
                  if (current)
                    Icon(Icons.check_rounded, size: 20, color: tokens.acc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Icon(icon, size: 22, color: tokens.acc),
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.acc,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
