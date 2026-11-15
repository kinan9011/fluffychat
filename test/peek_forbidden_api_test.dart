// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _files = [
  'lib/utils/chat_list/peek_controller.dart',
  'lib/utils/chat_list/peek_menu.dart',
  'lib/pages/chat_list/peek_sheet.dart',
];

const _forbidden = [
  'setReadMarker',
  'markUnread',
  'setTyping',
  'requestKeys',
  'requestHistory',
  'requestFuture',
  'postReceipt',
  'setPresence',
  'getEventContext',
  'eventContextId',
  'WidgetsBindingObserver',
  'didChangeAppLifecycleState',
  'PresenceBuilder',
  'HtmlMessage',
  'Linkify',
  'flutter_html',
  'fetchAggregatedEvents',
  'sendReadMarker',
  'sendTypingNotification',
  'pages/chat/',
  'presenceUserId',
  'requestUser',
  'getProfileFromUserId',
  'requestParticipants',
  'fetchCurrentPresence',
];

void main() {
  for (final path in _files) {
    test('$path calls nothing that others could notice', () {
      final source = File(path)
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final identifier in _forbidden) {
        expect(source, isNot(contains(identifier)), reason: identifier);
      }
    });
  }
}
