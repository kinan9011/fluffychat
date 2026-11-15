// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The keyboard and screen reader path to the message menu: the bubble takes
/// focus with Tab, Enter, the context menu key or Shift+F10 open the menu, and
/// assistive technology gets a named action next to the long press. Keys only
/// count while the bubble itself has focus, so Enter on a button inside the
/// bubble still activates that button. The tree is the same when [enabled] is
/// false, so selecting messages does not remount the bubbles.
class MessageFocus extends StatelessWidget {
  final bool enabled;
  final String actionLabel;
  final VoidCallback onOpenMenu;
  final Widget child;

  const MessageFocus({
    required this.enabled,
    required this.actionLabel,
    required this.onOpenMenu,
    required this.child,
    super.key,
  });

  bool _opensMenu(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.contextMenu) {
      return true;
    }
    return key == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    onLongPressHint: enabled ? actionLabel : null,
    customSemanticsActions: enabled
        ? {CustomSemanticsAction(label: actionLabel): onOpenMenu}
        : null,
    child: Focus(
      canRequestFocus: enabled,
      skipTraversal: !enabled,
      onKeyEvent: (node, event) {
        if (!enabled || !node.hasPrimaryFocus) return KeyEventResult.ignored;
        if (event is! KeyDownEvent || !_opensMenu(event)) {
          return KeyEventResult.ignored;
        }
        onOpenMenu();
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.banner),
            border: Focus.of(context).hasPrimaryFocus
                ? Border.all(color: AppTokens.of(context).acc, width: 2)
                : null,
          ),
          child: child,
        ),
      ),
    ),
  );
}
