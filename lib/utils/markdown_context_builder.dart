// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/composer/rich_text_editing_controller.dart';
import 'package:odango/utils/rich_text/format_range.dart';
import 'package:odango/utils/rich_text/rich_document.dart';

class MarkdownContextBuilder extends StatelessWidget {
  final EditableTextState editableTextState;
  final TextEditingController controller;
  final VoidCallback? onPasteImage;

  const MarkdownContextBuilder({
    required this.editableTextState,
    required this.controller,
    this.onPasteImage,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final value = editableTextState.textEditingValue;
    final selectedText = value.selection.textInside(value.text);
    final buttonItems = editableTextState.contextMenuButtonItems;
    final l10n = L10n.of(context);

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        ...buttonItems,
        if (onPasteImage != null)
          ContextMenuButtonItem(
            label: l10n.pasteImage,
            onPressed: () {
              ContextMenuController.removeAny();
              onPasteImage!();
            },
          ),
        if (selectedText.isNotEmpty &&
            controller is RichTextEditingController) ...[
          ContextMenuButtonItem(
            label: l10n.link,
            onPressed: () {
              ContextMenuController.removeAny();
              (controller as RichTextEditingController).toggleLink(context);
            },
          ),
          ContextMenuButtonItem(
            label: l10n.checkList,
            onPressed: () {
              ContextMenuController.removeAny();
              (controller as RichTextEditingController).toggleBlock(
                BlockKind.checklist,
              );
            },
          ),
          ContextMenuButtonItem(
            label: l10n.boldText,
            onPressed: () {
              ContextMenuController.removeAny();
              (controller as RichTextEditingController).toggleInline(
                RangeKind.bold,
              );
            },
          ),
          ContextMenuButtonItem(
            label: l10n.italicText,
            onPressed: () {
              ContextMenuController.removeAny();
              (controller as RichTextEditingController).toggleInline(
                RangeKind.italic,
              );
            },
          ),
          ContextMenuButtonItem(
            label: l10n.strikeThrough,
            onPressed: () {
              ContextMenuController.removeAny();
              (controller as RichTextEditingController).toggleInline(
                RangeKind.strike,
              );
            },
          ),
        ],
      ],
    );
  }
}
