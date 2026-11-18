// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:matrix/matrix.dart';

enum RowTick { none, sending, sent, read, error }

const _tickTypes = {
  EventTypes.Message,
  EventTypes.Encrypted,
  EventTypes.Sticker,
};

RowTick tickFor(Event? last, String? ownUserId) {
  if (last == null ||
      ownUserId == null ||
      last.senderId != ownUserId ||
      !_tickTypes.contains(last.type)) {
    return RowTick.none;
  }
  if (last.status.isError) return RowTick.error;
  if (!last.status.isSynced) return RowTick.sending;
  if (last.receipts.any((receipt) => receipt.user.id != ownUserId)) {
    return RowTick.read;
  }
  return RowTick.sent;
}

String chatRowSemantics(
  L10n l10n, {
  required String name,
  required int unread,
  required String preview,
  required String time,
  required bool pinned,
  required bool muted,
  required bool markedUnread,
  bool mentioned = false,
}) {
  final base = unread > 0
      ? l10n.chatRowSemantics(name, unread, preview, time)
      : l10n.chatRowSemanticsRead(name, preview, time);
  return [
    base,
    if (unread == 0 && markedUnread) l10n.unread,
    if (pinned) l10n.pinned,
    if (muted) l10n.muted,
    if (mentioned) l10n.mention,
  ].join(', ');
}
