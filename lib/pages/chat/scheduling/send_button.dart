// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/scheduling/send_options_flow.dart';

/// The round send button. While the send options are available a long press
/// (secondary click on desktop) opens them and a small clock marks it.
class SendButton extends StatelessWidget {
  const SendButton({required this.controller, required this.size, super.key});

  final ChatController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.sendController,
      builder: (context, _) => _button(context),
    );
  }

  Widget _button(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    IconButton build({String? tooltip}) => IconButton(
      key: const Key('send_button'),
      tooltip: tooltip,
      onPressed: controller.send,
      style: IconButton.styleFrom(
        backgroundColor: tokens.acc,
        foregroundColor: tokens.onacc,
        fixedSize: Size.square(size),
      ),
      icon: const Icon(Icons.send_rounded),
    );
    if (!controller.sendOptionsAvailable) return build(tooltip: l10n.send);
    // The button's own tooltip would take the long press for itself.
    final button = Tooltip(
      message: l10n.send,
      triggerMode: TooltipTriggerMode.manual,
      child: build(),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        MergeSemantics(
          child: GestureDetector(
            key: controller.sendButtonKey,
            behavior: HitTestBehavior.opaque,
            onLongPress: controller.onSendLongPress,
            onSecondaryTap: controller.onSendLongPress,
            child: Semantics(onLongPressHint: l10n.sendOptions, child: button),
          ),
        ),
        PositionedDirectional(
          top: 0,
          end: 0,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Container(
                key: const Key('send_options_badge'),
                width: AppSchedule.badge,
                height: AppSchedule.badge,
                decoration: BoxDecoration(
                  color: tokens.surf,
                  shape: BoxShape.circle,
                  boxShadow: AppElevation.bubble(tokens.shadow),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: AppSchedule.badgeIcon,
                  color: tokens.acc,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The clock in the composer pill: only while this chat has scheduled
/// messages, in the warning colour when one of them was not sent.
class ScheduledButton extends StatelessWidget {
  const ScheduledButton({
    required this.controller,
    required this.height,
    super.key,
  });

  final ChatController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: controller.scheduledCount,
      builder: (context, count, _) => count == 0
          ? const SizedBox.shrink()
          : ValueListenableBuilder<bool>(
              valueListenable: controller.scheduledFailed,
              builder: (context, failed, _) => SizedBox(
                width: 48,
                height: height,
                child: IconButton(
                  key: const Key('composer_scheduled_button'),
                  tooltip: L10n.of(context).scheduledMessages,
                  onPressed: controller.openScheduled,
                  icon: Icon(
                    Icons.schedule_send_rounded,
                    color: failed ? tokens.warn : tokens.mut,
                  ),
                ),
              ),
            ),
    );
  }
}
