// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/chat_wallpaper.dart';
import 'package:odango/pages/chat/scheduling/schedule_labels.dart';
import 'package:odango/pages/chat/scheduling/scheduled_messages_page.dart';
import 'package:odango/utils/account_config.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/date_time_extension.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/scheduling/schedule_time.dart';
import 'package:odango/utils/scheduling/scheduled_messages.dart';
import 'package:odango/widgets/glass_surface.dart';

class ScheduledMessagesView extends StatelessWidget {
  const ScheduledMessagesView(this.controller, {super.key});

  final ScheduledMessagesController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final list = c.list;
    final items = c.items;
    final hasDeviceEntry = items.any((i) => !i.onServer && !i.fromOtherDevice);
    return Scaffold(
      key: const Key('scheduled_messages_page'),
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: ChatWallpaper(
              config: c.room.client.applicationAccountConfig,
              client: c.room.client,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: AppChat.headerTopGap),
                _Header(controller: c),
                if (hasDeviceEntry)
                  _Banner(
                    key: const Key('scheduled_device_banner'),
                    icon: Icons.warning_amber_rounded,
                    text: l10n.scheduledDeviceBanner,
                  ),
                if (list?.serverListFailed == true)
                  _Banner(
                    key: const Key('scheduled_load_failed'),
                    icon: Icons.cloud_off_rounded,
                    text: l10n.scheduledLoadFailed,
                    actionLabel: l10n.tryAgain,
                    onAction: c.refresh,
                  ),
                Expanded(
                  child: list == null
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : items.isEmpty
                      ? _Empty(text: l10n.noScheduledMessages)
                      : _Groups(controller: c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final ScheduledMessagesController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final room = controller.room;
    final roomName = safeDisplayText(
      room.getLocalizedDisplayname(MatrixLocals(l10n)),
      maxGraphemes: 40,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Row(
        spacing: AppChat.headerGap,
        children: [
          SizedBox.square(
            dimension: AppChat.headerButton,
            child: GlassSurface(
              borderRadius: BorderRadius.circular(AppChat.headerButton / 2),
              child: IconButton(
                key: const Key('scheduled_back'),
                icon: Icon(Icons.arrow_back_rounded, color: tokens.fg),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.go('/rooms/${room.id}'),
              ),
            ),
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppChat.headerButton,
              ),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(AppChat.headerButton / 2),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 5, end: 14),
                  child: Row(
                    spacing: AppSpacing.m,
                    children: [
                      Container(
                        width: AppChat.headerAvatar,
                        height: AppChat.headerAvatar,
                        decoration: BoxDecoration(
                          color: tokens.accs,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.schedule_send_rounded,
                          size: 21,
                          color: tokens.acc,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.scheduledMessages,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.fg,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l10n.scheduledCount(
                                controller.items.length,
                                roomName,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: tokens.mut, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(
        start: AppSpacing.m,
        top: AppSpacing.s,
        end: AppSpacing.m,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.warnS,
        borderRadius: BorderRadius.circular(AppRadius.banner),
      ),
      child: Row(
        spacing: AppSpacing.m,
        children: [
          Icon(icon, size: 20, color: tokens.warn),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tokens.fg, fontSize: 13, height: 1.35),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!, style: TextStyle(color: tokens.acc)),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppRadius.menu),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.m,
            children: [
              Icon(Icons.schedule_send_rounded, size: 28, color: tokens.mut),
              Text(
                text,
                key: const Key('scheduled_empty'),
                style: TextStyle(
                  color: tokens.fg,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Groups extends StatelessWidget {
  const _Groups({required this.controller});

  final ScheduledMessagesController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final groups = groupByDay<ScheduledItem>(
      controller.items,
      (item) => item.sendAt,
    );
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.m,
        AppSpacing.xl,
        AppSpacing.m,
        AppSpacing.huge,
      ),
      children: [
        for (final group in groups)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
            child: Column(
              spacing: AppChat.groupGap,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.chip,
                    borderRadius: BorderRadius.circular(
                      AppSchedule.groupChipRadius,
                    ),
                  ),
                  child: Text(
                    group.day == null
                        ? l10n.scheduledWhenOnline(
                            controller.nameOf(group.items.first.untilOnline!),
                          )
                        : l10n.scheduledSendingOn(
                            scheduleDateLabel(context, group.day!),
                          ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final item in group.items)
                  _Entry(
                    key: ValueKey(
                      'scheduled_${item.local?.id ?? item.key.hashCode}',
                    ),
                    controller: controller,
                    item: item,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.controller, required this.item, super.key});

  final ScheduledMessagesController controller;
  final ScheduledItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final selected = c.selectedKey == item.key;
    final at = item.sendAt;
    final text = safeDisplayText(item.preview, maxGraphemes: 500);
    final time = at?.localizedTimeOfDay(context);
    final shown = text.isEmpty ? l10n.scheduledFromOtherDevice : text;
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width * AppSchedule.bubbleMaxFraction,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: AppChat.groupGap,
          children: [
            Semantics(
              button: true,
              selected: selected,
              label: time == null ? shown : '$shown, $time',
              excludeSemantics: true,
              onTap: () => c.select(item),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => c.select(item),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsetsDirectional.fromSTEB(13, 8, 13, 6),
                  decoration: BoxDecoration(
                    color: tokens.outS,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(AppRadius.bubble),
                      topEnd: Radius.circular(AppRadius.bubble),
                      bottomStart: Radius.circular(AppRadius.bubble),
                      bottomEnd: Radius.circular(AppRadius.bubbleTail),
                    ),
                    border: selected
                        ? Border.all(color: tokens.acc, width: 2)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(
                        shown,
                        style: TextStyle(
                          color: tokens.outFg,
                          fontSize: 15.5,
                          height: 1.35,
                          fontStyle: text.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                      if (text.isNotEmpty && item.fromOtherDevice)
                        Text(
                          l10n.scheduledFromOtherDevice,
                          style: TextStyle(color: tokens.outMut, fontSize: 11),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 3,
                          children: [
                            if (time != null)
                              Text(
                                time,
                                style: TextStyle(
                                  color: tokens.outMut,
                                  fontSize: 11,
                                ),
                              ),
                            Icon(
                              item.untilOnline == null
                                  ? Icons.schedule_rounded
                                  : Icons.person_rounded,
                              size: 14,
                              color: tokens.outMut,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (item.failed)
              _Notice(
                icon: Icons.error_outline_rounded,
                text: scheduleFailureMessage(context, item.local!),
              ),
            if (item.sendsUnencrypted)
              _Notice(
                icon: Icons.lock_open_rounded,
                text: l10n.scheduledUnencrypted,
              ),
            if (selected)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppChat.groupGap,
                children: [
                  _Chip(
                    key: const Key('scheduled_send_now'),
                    icon: Icons.send_rounded,
                    label: l10n.scheduledSendNow,
                    onTap: c.sendNow,
                  ),
                  if (item.canReschedule)
                    _Chip(
                      key: const Key('scheduled_reschedule'),
                      icon: Icons.edit_calendar_rounded,
                      label: l10n.scheduledReschedule,
                      onTap: c.reschedule,
                    ),
                  _Chip(
                    key: const Key('scheduled_delete'),
                    icon: Icons.delete_rounded,
                    semanticsLabel: l10n.delete,
                    destructive: true,
                    onTap: c.delete,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GlassSurface(
      solid: true,
      borderRadius: BorderRadius.circular(AppSchedule.chipRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xs,
          children: [
            Icon(icon, size: 16, color: tokens.warn),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: tokens.fg, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.onTap,
    this.label,
    this.semanticsLabel,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String? label;
  final String? semanticsLabel;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = destructive ? tokens.red : tokens.fg;
    return Semantics(
      button: true,
      label: label ?? semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: GlassSurface(
              solid: true,
              borderRadius: BorderRadius.circular(AppSchedule.chipRadius),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: label == null ? 10 : 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(
                      icon,
                      size: AppSchedule.actionIcon,
                      color: destructive ? tokens.red : tokens.acc,
                    ),
                    if (label != null)
                      Text(
                        label!,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
