// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/scheduling/schedule_labels.dart';
import 'package:odango/pages/chat/scheduling/schedule_sheet.dart';
import 'package:odango/pages/chat/scheduling/send_options_menu.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/rich_text/html_serializer.dart';
import 'package:odango/utils/scheduling/scheduled_content.dart';
import 'package:odango/utils/scheduling/scheduled_messages.dart';
import 'package:odango/utils/scheduling/send_options.dart';

/// The partner of a direct chat when their presence is known and not online.
/// Only what is cached counts: the menu never waits for the network.
@visibleForTesting
Future<String?> offlinePartnerOf(Room room) async {
  final partner = room.directChatMatrixID;
  if (partner == null || partner == room.client.userID) return null;
  try {
    final presence = await room.client.fetchCurrentPresence(
      partner,
      fetchOnlyFromCached: true,
    );
    return presenceKnownOffline(
          online: presence.presence == PresenceType.online,
          lastActive: presence.lastActiveTimestamp,
        )
        ? partner
        : null;
  } catch (_) {
    return null;
  }
}

/// Holding the send button: send without sound, schedule, send when online.
/// All three build the content once ([ScheduledContent.build]) and keep the
/// text in the composer until it is out or stored.
extension SendOptionsFlow on ChatController {
  List<SendOption> _options({required bool partnerOffline}) =>
      availableSendOptions(
        text: sendController.text,
        editing: editEvent != null,
        canSend: room.canSendDefaultMessages,
        partnerPresenceKnownOffline: partnerOffline,
      );

  bool get sendOptionsAvailable => _options(partnerOffline: false).isNotEmpty;

  Rect? _sendButtonRect() {
    final box = sendButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> onSendLongPress() async {
    if (!sendOptionsAvailable) return;
    unawaited(HapticFeedback.lightImpact());
    final partner = await offlinePartnerOf(room);
    final anchor = _sendButtonRect();
    final options = _options(partnerOffline: partner != null);
    if (!mounted || anchor == null || options.isEmpty) return;
    final partnerName = partner == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(partner).calcDisplayname();
    final choice = await showSendOptionsMenu(
      context,
      options: options,
      anchor: anchor,
      partnerName: partnerName == null
          ? null
          : safeDisplayText(partnerName, maxGraphemes: 30),
    );
    if (choice == null || !mounted) return;
    final outgoing = await planComposerOutgoing();
    if (outgoing == null || !mounted) return;
    final Map<String, Object?> content;
    try {
      content = ScheduledContent.build(
        room,
        outgoing,
        inReplyTo: replyEvent,
        threadRootEventId: activeThreadId,
        silent: choice == SendOption.silent,
      );
    } on RichTextTooLong {
      await _tell(L10n.of(context).scheduleMessageTooLong);
      return;
    }
    try {
      switch (choice) {
        case SendOption.silent:
          unawaited(room.sendEvent(Map<String, dynamic>.of(content)));
          finishOptionsSend();
        case SendOption.schedule:
          await _schedule(content);
        case SendOption.whenOnline:
          await scheduledMessages.scheduleWhenOnline(room, content, partner!);
          if (!mounted) return;
          final l10n = L10n.of(context);
          finishOptionsSend();
          await _tell(l10n.waitingUntilOnline(partnerName ?? ''));
      }
    } on ScheduleException catch (e) {
      if (!mounted) return;
      await _tell(scheduleErrorMessage(L10n.of(context), e));
    }
  }

  Future<void> _schedule(Map<String, Object?> content) async {
    final mode = await scheduledMessages.modeFor();
    if (!mounted) return;
    final at = await showScheduleSheet(
      context,
      preview: safeDisplayText(
        ScheduledContent.previewOf(content),
        maxGraphemes: 120,
      ),
      mode: mode,
      encrypted: room.encrypted,
    );
    if (at == null || !mounted) return;
    await scheduledMessages.schedule(room, content, at, mode);
    if (!mounted) return;
    final l10n = L10n.of(context);
    final label = scheduleFullLabel(context, at);
    finishOptionsSend();
    await _tell(l10n.scheduledFor(label));
  }

  Future<void> _tell(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        margin: const EdgeInsetsDirectional.only(
          start: AppSpacing.xxl,
          top: AppSpacing.xxl,
          end: AppSpacing.xxl,
          bottom: AppChat.composerHeight + AppSpacing.huge,
        ),
        content: Text(message),
      ),
    );
  }

  void openScheduled() => context.go('/rooms/${room.id}/scheduled');
}
