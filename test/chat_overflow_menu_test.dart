// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/chat_overflow_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<ChatOverflowAction> actions({
    bool muted = false,
    bool canCall = false,
    bool showDetails = false,
    bool joined = true,
    bool left = false,
  }) => chatOverflowActions(
    muted: muted,
    canCall: canCall,
    showDetails: showDetails,
    joined: joined,
    left: left,
  );

  test('joined room, nothing special', () {
    expect(actions(), [
      ChatOverflowAction.mute,
      ChatOverflowAction.search,
      ChatOverflowAction.disappearing,
      ChatOverflowAction.wallpaper,
      ChatOverflowAction.exportChat,
      ChatOverflowAction.encryption,
      ChatOverflowAction.leave,
    ]);
  });

  test('export is offered for joined rooms only (the page needs a join)', () {
    expect(actions(), contains(ChatOverflowAction.exportChat));
    expect(
      actions(joined: false, left: true),
      isNot(contains(ChatOverflowAction.exportChat)),
    );
    expect(
      actions(joined: false),
      isNot(contains(ChatOverflowAction.exportChat)),
    );
  });

  test('disappearing messages are offered in joined rooms only', () {
    expect(actions(), contains(ChatOverflowAction.disappearing));
    expect(
      actions(joined: false),
      isNot(contains(ChatOverflowAction.disappearing)),
    );
    expect(
      actions(joined: false, left: true),
      isNot(contains(ChatOverflowAction.disappearing)),
    );
  });

  test('muted shows unmute instead of mute', () {
    expect(actions(muted: true).first, ChatOverflowAction.unmute);
    expect(actions(muted: true), isNot(contains(ChatOverflowAction.mute)));
  });

  test('video call only when the room can be called', () {
    expect(actions(), isNot(contains(ChatOverflowAction.videoCall)));
    expect(
      actions(canCall: true),
      containsAllInOrder([
        ChatOverflowAction.mute,
        ChatOverflowAction.videoCall,
        ChatOverflowAction.search,
      ]),
    );
  });

  test('details only in column layouts for joined rooms', () {
    expect(actions(), isNot(contains(ChatOverflowAction.details)));
    expect(
      actions(showDetails: true),
      containsAllInOrder([
        ChatOverflowAction.wallpaper,
        ChatOverflowAction.exportChat,
        ChatOverflowAction.details,
        ChatOverflowAction.encryption,
      ]),
    );
    expect(
      actions(showDetails: true, joined: false),
      isNot(contains(ChatOverflowAction.details)),
    );
  });

  test('an invite cannot be muted, searched or inspected', () {
    expect(actions(joined: false), [
      ChatOverflowAction.wallpaper,
      ChatOverflowAction.leave,
    ]);
  });

  test('a left room can still search and show encryption', () {
    expect(
      actions(joined: false, left: true),
      containsAll([ChatOverflowAction.search, ChatOverflowAction.encryption]),
    );
  });

  test('leave is always last', () {
    for (final muted in [true, false]) {
      for (final canCall in [true, false]) {
        expect(
          actions(muted: muted, canCall: canCall, showDetails: true).last,
          ChatOverflowAction.leave,
        );
      }
    }
  });
}
