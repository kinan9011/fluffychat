// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/composer/rich_text_editing_controller.dart';
import 'package:fluffychat/utils/rich_text/editor_text.dart';
import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/rich_document.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:material_ui/material_ui.dart';

/// Format bar over a text selection in the composer (DESIGN 9.7). Shown only
/// while the field has focus and a range is selected.
class QuickFormatBar extends StatelessWidget {
  const QuickFormatBar({
    required this.controller,
    required this.focusNode,
    super.key,
  });

  final RichTextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, focusNode]),
    builder: (context, _) {
      final selection = controller.selection;
      if (!focusNode.hasFocus || !selection.isValid || selection.isCollapsed) {
        return const SizedBox.shrink();
      }
      final l10n = L10n.of(context);
      final quote = controller.caretLine?.kind == LineKind.quote;
      final items = [
        (
          'bold',
          Icons.format_bold_rounded,
          l10n.boldText,
          controller.isActive(RangeKind.bold),
          () => controller.toggleInline(RangeKind.bold),
        ),
        (
          'italic',
          Icons.format_italic_rounded,
          l10n.italicText,
          controller.isActive(RangeKind.italic),
          () => controller.toggleInline(RangeKind.italic),
        ),
        (
          'underline',
          Icons.format_underlined_rounded,
          l10n.underlineText,
          controller.isActive(RangeKind.underline),
          () => controller.toggleInline(RangeKind.underline),
        ),
        (
          'strike',
          Icons.strikethrough_s_rounded,
          l10n.strikeThrough,
          controller.isActive(RangeKind.strike),
          () => controller.toggleInline(RangeKind.strike),
        ),
        (
          'spoiler',
          Icons.visibility_off_rounded,
          l10n.spoiler,
          controller.isActive(RangeKind.spoiler),
          () => controller.toggleInline(RangeKind.spoiler),
        ),
        (
          'code',
          Icons.code_rounded,
          l10n.inlineCode,
          controller.isActive(RangeKind.code),
          () => controller.toggleInline(RangeKind.code),
        ),
        (
          'link',
          Icons.link_rounded,
          l10n.link,
          controller.isActive(RangeKind.link),
          () => controller.toggleLink(context),
        ),
        (
          'quote',
          Icons.format_quote_rounded,
          l10n.quote,
          quote,
          () => controller.toggleBlock(BlockKind.quote),
        ),
      ];
      return GlassSurface(
        blur: 24,
        borderRadius: BorderRadius.circular(AppChat.quickBarRadius),
        child: SizedBox(
          height: AppChat.quickBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                for (final (name, icon, label, active, onTap) in items)
                  Expanded(
                    key: ValueKey('quick_$name'),
                    child: _QuickButton(
                      icon: icon,
                      label: label,
                      active: active,
                      onTap: onTap,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          canRequestFocus: false,
          radius: 22,
          child: Center(
            child: Container(
              width: AppChat.quickBarButton,
              height: AppChat.quickBarButton,
              decoration: BoxDecoration(
                color: active ? tokens.accs : null,
                borderRadius: BorderRadius.circular(
                  AppChat.quickBarButtonRadius,
                ),
              ),
              child: Icon(
                icon,
                size: 21,
                color: active ? tokens.acc : tokens.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
