// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Privacy signals leave the client through one place each. A new call site
/// somewhere else would bypass the settings, so the scan fails on it.
List<String> _callSites(Pattern pattern) {
  final hits = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/l10n/')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('//')) continue;
      if (line.contains(pattern)) hits.add('${entity.path}:${i + 1}');
    }
  }
  return hits;
}

Set<String> _files(List<String> sites) =>
    sites.map((site) => site.split(':').first).toSet();

void main() {
  test('read receipts are posted only by sendReadMarker', () {
    final sites = _callSites(
      RegExp(r'(?<!controller)\.(setReadMarker|postReceipt)\('),
    );
    expect(_files(sites), {'lib/utils/privacy/read_markers.dart'});
  });

  test('the sync presence is written only by the presence policy, the client '
      'factory and the background fetch mode', () {
    final sites = _callSites(RegExp(r'\.syncPresence\s*='));
    expect(_files(sites), {
      'lib/utils/privacy/presence_policy.dart',
      'lib/utils/client_manager.dart',
      'lib/main.dart',
    });
    final main = sites.where((s) => s.startsWith('lib/main.dart')).length;
    expect(main, 2);
  });

  test('the presence status is published only through the policy', () {
    final sites = _callSites(RegExp(r'\.setPresence\('));
    expect(_files(sites), {
      'lib/utils/privacy/presence_policy.dart',
      'lib/pages/chat_list/chat_list.dart',
    });
    final chatList = File(
      'lib/pages/chat_list/chat_list.dart',
    ).readAsStringSync();
    expect(chatList, contains('PresencePolicy.fromSettings().statusPresence'));
  });

  test('typing notifications are sent only through the notifier', () {
    final sites = _callSites(RegExp(r'\.setTyping\('));
    expect(_files(sites), {'lib/pages/chat/chat.dart'});
    final chat = File('lib/pages/chat/chat.dart').readAsStringSync();
    expect(
      chat,
      contains(
        'send: (typing, {timeoutMs}) => room.setTyping(typing, timeout: timeoutMs)',
      ),
    );
  });

  test('main.dart uses the policy for the foreground switch', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('syncPresence = backgroundFetchPresence'));
    expect(main, contains('PresencePolicy.fromSettings().syncPresence('));
  });

  test('no read receipt is forced public at a call site', () {
    final sites = _callSites('sendReadMarker(');
    for (final file in _files(sites)) {
      expect(
        File(file).readAsStringSync(),
        isNot(contains('public: true')),
        reason: file,
      );
    }
  });

  test('clients made for a background isolate or the background fetch mode '
      'start offline', () {
    final counts = {
      'lib/main.dart': 1,
      'lib/utils/push_helper.dart': 2,
      'lib/utils/notification_background_handler.dart': 2,
    };
    for (final entry in counts.entries) {
      final text = File(entry.key).readAsStringSync();
      expect(
        'background: true'.allMatches(text).length,
        entry.value,
        reason: entry.key,
      );
    }
    final manager = File('lib/utils/client_manager.dart').readAsStringSync();
    expect(
      manager,
      contains('createClient(name, store, background: background)'),
    );
  });
}
