// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

void main() {
  late RecordingApi api;
  late Client client;

  setUp(() async {
    api = RecordingApi();
    client = await prepareTestClient(httpClient: api);
    await AppSettings.store.clear();
    client.backgroundSync = false;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() => client.dispose(closeDatabase: true));

  Future<Map<String, String>> syncQuery() async {
    api.clear();
    try {
      await client.oneShotSync();
    } catch (_) {}
    final syncs = api.requests('/sync');
    expect(syncs, isNotEmpty);
    return syncs.last.url.queryParameters;
  }

  const hidden = PresencePolicy(shareOnlineStatus: false, appearOffline: false);
  const appearOffline = PresencePolicy(
    shareOnlineStatus: true,
    appearOffline: true,
  );
  const visible = PresencePolicy(shareOnlineStatus: true, appearOffline: false);

  for (final foreground in [true, false]) {
    final where = foreground ? 'foreground' : 'background';
    test('hidden by default, $where: the sync asks for offline', () async {
      await PresenceApplier.apply(
        [client],
        foreground: foreground,
        policy: hidden,
      );
      expect((await syncQuery())['set_presence'], 'offline');
    });

    test('appear offline, $where: the sync asks for offline', () async {
      await PresenceApplier.apply(
        [client],
        foreground: foreground,
        policy: appearOffline,
      );
      expect((await syncQuery())['set_presence'], 'offline');
    });
  }

  test('visible in the foreground: the sync never asks for offline', () async {
    await PresenceApplier.apply([client], foreground: true, policy: visible);
    expect((await syncQuery()).containsKey('set_presence'), isFalse);
  });

  test('visible in the background: away', () async {
    await PresenceApplier.apply([client], foreground: false, policy: visible);
    expect((await syncQuery())['set_presence'], 'unavailable');
  });

  test('hidden: no request ever sets the presence to online', () async {
    api.clear();
    await PresenceApplier.apply([client], foreground: true, policy: hidden);
    await PresenceApplier.apply([client], foreground: false, policy: hidden);
    await syncQuery();
    for (final request in api.requests('/presence/', method: 'PUT')) {
      expect((request.json! as Map)['presence'], 'offline');
    }
    for (final sync in api.requests('/sync')) {
      expect(sync.url.queryParameters['set_presence'], 'offline');
    }
  });
}
