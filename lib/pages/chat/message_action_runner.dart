// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/chat/message_actions.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:matrix/matrix.dart';

MessageActionContext messageActionContext(ChatController c, Event event) {
  if (event.redacted) return const MessageActionContext(canSelect: false);
  final room = c.room;
  final sent = event.status.isSent;
  final canWrite = room.canSendDefaultMessages && !c.isArchived;
  final readable = !event.isUndecryptable;
  return MessageActionContext(
    canSelect: readable,
    canReply: canWrite && sent,
    canThread: canWrite && sent && c.activeThreadId == null,
    canEdit: readable && c.canEditEvent(event),
    canCopy: readable,
    canSave: readable && c.canSaveEvent(event),
    canPin: readable && c.canPinEvent(event),
    isPinned: room.pinnedEventIds.contains(event.eventId),
    canForward: readable && sent,
    canReport: sent,
    canRedact: c.canRedactEvents([event]),
  );
}

/// The controller methods behind the menu work on the selection, so the
/// pressed message is selected first and the selection is cleared again
/// afterwards, except for Select, which is how multi-select starts.
Future<void> runMessageAction(
  ChatController c,
  MessageAction action,
  Event event,
) async {
  switch (action) {
    case MessageAction.reply:
      c.replyAction(replyTo: event);
    case MessageAction.replyInThread:
      c.enterThread(event.eventId);
    case MessageAction.info:
      c.showEventInfo(event);
    case MessageAction.select:
      c.selectOnly(event);
    case MessageAction.edit:
      c.selectOnly(event);
      c.editSelectedEventAction();
    case MessageAction.copy:
      c.selectOnly(event);
      c.copyEventsAction();
    case MessageAction.saveFile:
      c.selectOnly(event);
      c.saveSelectedEvent(c.context);
      c.clearSelectedEvents();
    case MessageAction.pin:
    case MessageAction.unpin:
      c.selectOnly(event);
      c.pinEvent();
      c.clearSelectedEvents();
    case MessageAction.forward:
      c.selectOnly(event);
      await c.forwardEventsAction();
      if (c.mounted) c.clearSelectedEvents();
    case MessageAction.report:
      c.selectOnly(event);
      await c.reportEventAction();
      if (c.mounted) c.clearSelectedEvents();
    case MessageAction.delete:
      c.selectOnly(event);
      await c.redactEventsAction();
      if (c.mounted) c.clearSelectedEvents();
  }
}
