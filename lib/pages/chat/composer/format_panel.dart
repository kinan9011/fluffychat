// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/composer/rich_text_editing_controller.dart';
import 'package:odango/utils/rich_text/editor_text.dart';
import 'package:odango/utils/rich_text/format_range.dart';
import 'package:odango/utils/rich_text/rich_document.dart';
import 'package:odango/widgets/glass_surface.dart';

class _Cell {
  const _Cell(this.name, this.icon, this.label, this.active, this.onTap);

  final String name;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
}

/// The Aa panel (DESIGN 7.12, 9.7): undo/redo and the 14 format controls.
class FormatPanel extends StatelessWidget {
  const FormatPanel({
    required this.controller,
    this.availableHeight = double.infinity,
    super.key,
  });

  final RichTextEditingController controller;
  final double availableHeight;

  List<_Cell> _cells(BuildContext context) {
    final l10n = L10n.of(context);
    final line = controller.caretLine;
    bool block(LineKind kind) => line?.kind == kind;
    final heading = block(LineKind.heading)
        ? l10n.headingLevel(line!.level)
        : l10n.heading;
    return [
      _Cell(
        'bold',
        Icons.format_bold_rounded,
        l10n.boldText,
        controller.isActive(RangeKind.bold),
        () => controller.toggleInline(RangeKind.bold),
      ),
      _Cell(
        'italic',
        Icons.format_italic_rounded,
        l10n.italicText,
        controller.isActive(RangeKind.italic),
        () => controller.toggleInline(RangeKind.italic),
      ),
      _Cell(
        'underline',
        Icons.format_underlined_rounded,
        l10n.underlineText,
        controller.isActive(RangeKind.underline),
        () => controller.toggleInline(RangeKind.underline),
      ),
      _Cell(
        'strike',
        Icons.strikethrough_s_rounded,
        l10n.strikeThrough,
        controller.isActive(RangeKind.strike),
        () => controller.toggleInline(RangeKind.strike),
      ),
      _Cell(
        'code',
        Icons.code_rounded,
        l10n.inlineCode,
        controller.isActive(RangeKind.code),
        () => controller.toggleInline(RangeKind.code),
      ),
      _Cell(
        'spoiler',
        Icons.visibility_off_rounded,
        l10n.spoiler,
        controller.isActive(RangeKind.spoiler),
        () => controller.toggleInline(RangeKind.spoiler),
      ),
      _Cell(
        'link',
        Icons.link_rounded,
        l10n.link,
        controller.isActive(RangeKind.link),
        () => controller.toggleLink(context),
      ),
      _Cell(
        'heading',
        Icons.title_rounded,
        heading,
        block(LineKind.heading),
        () => controller.toggleBlock(BlockKind.heading),
      ),
      _Cell(
        'quote',
        Icons.format_quote_rounded,
        l10n.quote,
        block(LineKind.quote),
        () => controller.toggleBlock(BlockKind.quote),
      ),
      _Cell(
        'bullet',
        Icons.format_list_bulleted_rounded,
        l10n.bulletedList,
        block(LineKind.bullet),
        () => controller.toggleBlock(BlockKind.bullet),
      ),
      _Cell(
        'ordered',
        Icons.format_list_numbered_rounded,
        l10n.numberedList,
        block(LineKind.ordered),
        () => controller.toggleBlock(BlockKind.ordered),
      ),
      _Cell(
        'checklist',
        Icons.checklist_rounded,
        l10n.checkList,
        block(LineKind.checklist),
        () => controller.toggleBlock(BlockKind.checklist),
      ),
      _Cell(
        'codeBlock',
        Icons.data_object_rounded,
        l10n.codeBlock,
        false,
        () => controller.insertBlockFence(BlockKind.codeBlock),
      ),
      _Cell(
        'maths',
        Icons.functions_rounded,
        l10n.maths,
        controller.isActive(RangeKind.maths),
        () => controller.toggleInline(RangeKind.maths),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (availableHeight - AppChat.formatPanelReserve).clamp(
          AppChat.formatPanelMinHeight,
          AppChat.formatPanelMaxHeight,
        ),
      ),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppChat.formatPanelRadius),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(AppChat.formatPanelPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: Text(
                          l10n.formatting,
                          style: TextStyle(
                            color: tokens.mut,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    _HistoryButton(
                      key: const ValueKey('format_undo'),
                      icon: Icons.undo_rounded,
                      label: l10n.undo,
                      onTap: controller.canUndo ? controller.undo : null,
                    ),
                    _HistoryButton(
                      key: const ValueKey('format_redo'),
                      icon: Icons.redo_rounded,
                      label: l10n.redo,
                      onTap: controller.canRedo ? controller.redo : null,
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: AppChat.formatGap,
                      children: [
                        for (final row in _rows(_cells(context)))
                          Row(
                            children: [
                              for (final cell in row)
                                Expanded(
                                  child: _FormatCell(
                                    key: ValueKey('format_${cell.name}'),
                                    cell: cell,
                                  ),
                                ),
                            ],
                          ),
                      ],
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

  static const _columns = 7;

  static Iterable<List<_Cell>> _rows(List<_Cell> cells) sync* {
    for (var i = 0; i < cells.length; i += _columns) {
      yield cells.sublist(i, i + _columns);
    }
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          canRequestFocus: false,
          radius: 22,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              icon,
              size: 21,
              color: onTap == null
                  ? tokens.mut.withValues(alpha: .5)
                  : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatCell extends StatelessWidget {
  const _FormatCell({required this.cell, super.key});

  final _Cell cell;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: cell.active,
      label: cell.label,
      onTap: cell.onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: cell.label,
        child: InkResponse(
          onTap: cell.onTap,
          canRequestFocus: false,
          radius: 22,
          child: SizedBox(
            height: 44,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppChat.formatCell),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cell.active ? tokens.acc : tokens.surf2,
                      borderRadius: BorderRadius.circular(
                        AppChat.formatCellRadius,
                      ),
                    ),
                    child: Icon(
                      cell.icon,
                      size: 21,
                      color: cell.active ? tokens.onacc : tokens.fg,
                    ),
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
