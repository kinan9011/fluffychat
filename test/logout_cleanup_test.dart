// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/logout_cleanup.dart';
import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late List<String> deletedQuarantine;
  late int notificationsCancelled;
  late LogoutCleanup cleanup;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'draft_!a:example.org': 'legacy plaintext draft',
      'draft_!b:example.org': 'another one',
      'unrelated': 'stays',
    });
    await AppSettings.init(loadWebConfigFile: false);
    prefs = AppSettings.store;
    await AppSettings.databaseQuarantinedClients.setItem(['alice', 'bob']);
    deletedQuarantine = [];
    notificationsCancelled = 0;
    cleanup = LogoutCleanup(
      deleteQuarantined: (name) async => deletedQuarantine.add(name),
      cancelNotifications: () async => notificationsCancelled++,
      prefs: prefs,
      status: StatusClearStore(),
    );
  });

  test('removes what this account left on the device', () async {
    await StatusClearStore().arm(
      '@alice:example.org',
      'busy',
      DateTime.now().add(const Duration(hours: 1)),
    );
    await StatusClearStore().arm(
      '@bob:example.org',
      'away',
      DateTime.now().add(const Duration(hours: 1)),
    );
    await cleanup.run(
      clientName: 'alice',
      userId: '@alice:example.org',
      lastAccount: false,
    );
    expect(deletedQuarantine, ['alice']);
    expect(AppSettings.databaseQuarantinedClients.value, ['bob']);
    expect(StatusClearStore().read().map((r) => r.userId), [
      '@bob:example.org',
    ]);
    expect(prefs.getString('draft_!a:example.org'), isNotNull);
    expect(notificationsCancelled, 0);
  });

  test(
    'the last account also clears legacy drafts and notifications',
    () async {
      await cleanup.run(
        clientName: 'alice',
        userId: '@alice:example.org',
        lastAccount: true,
      );
      expect(prefs.getKeys().where((k) => k.startsWith('draft_')), isEmpty);
      expect(prefs.getString('unrelated'), 'stays');
      expect(notificationsCancelled, 1);
    },
  );

  test('an unknown user id skips the per-user steps only', () async {
    await cleanup.run(clientName: 'alice', userId: null, lastAccount: false);
    expect(deletedQuarantine, ['alice']);
  });

  test('one failing step never stops the others and never throws', () async {
    final failing = LogoutCleanup(
      deleteQuarantined: (_) async => throw StateError('disk'),
      cancelNotifications: () async => throw StateError('plugin'),
      prefs: prefs,
      status: StatusClearStore(),
    );
    await failing.run(
      clientName: 'alice',
      userId: '@alice:example.org',
      lastAccount: true,
    );
    expect(prefs.getKeys().where((k) => k.startsWith('draft_')), isEmpty);
  });
}
