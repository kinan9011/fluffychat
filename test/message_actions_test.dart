// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/message_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing is possible: select and info remain', () {
    expect(availableMessageActions(const MessageActionContext()), [
      MessageAction.select,
      MessageAction.info,
    ]);
  });

  test('own text message in a room you can write in', () {
    expect(
      availableMessageActions(
        const MessageActionContext(
          canReply: true,
          canThread: true,
          canEdit: true,
          canCopy: true,
          canPin: true,
          canForward: true,
          canRedact: true,
          canReport: true,
        ),
      ),
      [
        MessageAction.reply,
        MessageAction.replyInThread,
        MessageAction.edit,
        MessageAction.copy,
        MessageAction.pin,
        MessageAction.forward,
        MessageAction.select,
        MessageAction.info,
        MessageAction.report,
        MessageAction.delete,
      ],
    );
  });

  test('a pinned message offers unpin instead of pin', () {
    final actions = availableMessageActions(
      const MessageActionContext(canPin: true, isPinned: true),
    );
    expect(actions, contains(MessageAction.unpin));
    expect(actions, isNot(contains(MessageAction.pin)));
  });

  test('a file can be saved, a text cannot', () {
    expect(
      availableMessageActions(const MessageActionContext(canSave: true)),
      contains(MessageAction.saveFile),
    );
    expect(
      availableMessageActions(const MessageActionContext()),
      isNot(contains(MessageAction.saveFile)),
    );
  });

  test('delete is last whatever else is there', () {
    for (final canReport in [true, false]) {
      final actions = availableMessageActions(
        MessageActionContext(canReport: canReport, canRedact: true),
      );
      expect(actions.last, MessageAction.delete);
    }
  });

  test('a message nobody may delete has no delete entry', () {
    expect(
      availableMessageActions(const MessageActionContext(canReport: true)),
      isNot(contains(MessageAction.delete)),
    );
  });

  test('a context that cannot select offers only info', () {
    expect(
      availableMessageActions(const MessageActionContext(canSelect: false)),
      [MessageAction.info],
    );
  });
}
