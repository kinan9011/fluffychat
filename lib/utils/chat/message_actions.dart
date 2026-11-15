// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

enum MessageAction {
  reply,
  replyInThread,
  edit,
  copy,
  saveFile,
  pin,
  unpin,
  forward,
  select,
  info,
  report,
  delete,
}

class MessageActionContext {
  final bool canSelect;
  final bool canReply;
  final bool canThread;
  final bool canEdit;
  final bool canCopy;
  final bool canSave;
  final bool canPin;
  final bool isPinned;
  final bool canForward;
  final bool canReport;
  final bool canRedact;

  const MessageActionContext({
    this.canSelect = true,
    this.canReply = false,
    this.canThread = false,
    this.canEdit = false,
    this.canCopy = false,
    this.canSave = false,
    this.canPin = false,
    this.isPinned = false,
    this.canForward = false,
    this.canReport = false,
    this.canRedact = false,
  });
}

/// The entries of the long-press menu, in order. Info is always there, the
/// destructive entry is always last.
List<MessageAction> availableMessageActions(MessageActionContext c) => [
  if (c.canReply) MessageAction.reply,
  if (c.canThread) MessageAction.replyInThread,
  if (c.canEdit) MessageAction.edit,
  if (c.canCopy) MessageAction.copy,
  if (c.canSave) MessageAction.saveFile,
  if (c.canPin) c.isPinned ? MessageAction.unpin : MessageAction.pin,
  if (c.canForward) MessageAction.forward,
  if (c.canSelect) MessageAction.select,
  MessageAction.info,
  if (c.canReport) MessageAction.report,
  if (c.canRedact) MessageAction.delete,
];
