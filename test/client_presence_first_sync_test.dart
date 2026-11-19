// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/client_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'utils/recording_api.dart';
import 'utils/set_up_vodozemac.dart';
import 'utils/test_client.dart';

void main() {
  late RecordingApi api;
  late Client client;

  setUp(() async {
    await setUpVodozemac();
    api = RecordingApi();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
  });

  tearDown(() => client.dispose(closeDatabase: true));

  Future<void> firstSync({bool background = false}) async {
    client = await ClientManager.createClient(
      'presence-first-sync',
      AppSettings.store,
      background: background,
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'presence-first-sync',
        database: await databaseFactoryFfi.openDatabase(
          ':memory:',
          options: OpenDatabaseOptions(singleInstance: false),
        ),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    client.backgroundSync = false;
    api.clear();
    await client.init(
      newHomeserver: Uri.parse('https://fakeServer.notExisting'),
      newDeviceID: 'ABCD1234',
      newDeviceName: 'Presence Tester',
      newToken: '1234',
      newUserID: '@test:fakeServer.notExisting',
      newOlmAccount: pickledOlmAccount,
    );
  }

  test('a hidden user (the default): the very first sync asks for offline '
      'and nothing ever sets online', () async {
    await firstSync();
    final syncs = api.requests('/sync');
    expect(syncs, isNotEmpty);
    expect(syncs.first.url.queryParameters['set_presence'], 'offline');
    for (final put in api.requests('/presence/', method: 'PUT')) {
      expect((put.json! as Map)['presence'], isNot('online'));
    }
  });

  test('sharing the online status: the first sync does not ask for offline, '
      'as before', () async {
    await AppSettings.shareOnlineStatus.setItem(true);
    await firstSync();
    expect(
      api
          .requests('/sync')
          .first
          .url
          .queryParameters
          .containsKey('set_presence'),
      isFalse,
    );
  });

  test('a background client keeps offline even when the user shares the '
      'status', () async {
    await AppSettings.shareOnlineStatus.setItem(true);
    await firstSync(background: true);
    expect(
      api.requests('/sync').first.url.queryParameters['set_presence'],
      'offline',
    );
  });

  test(
    'Away while sharing: the very first sync asks for unavailable',
    () async {
      await AppSettings.shareOnlineStatus.setItem(true);
      await AppSettings.presenceAway.setItem(true);
      await firstSync();
      expect(
        api.requests('/sync').first.url.queryParameters['set_presence'],
        'unavailable',
      );
      for (final put in api.requests('/presence/', method: 'PUT')) {
        expect((put.json! as Map)['presence'], isNot('online'));
      }
    },
  );

  test('Away never makes a hidden user visible on the first sync', () async {
    await AppSettings.presenceAway.setItem(true);
    await firstSync();
    expect(
      api.requests('/sync').first.url.queryParameters['set_presence'],
      'offline',
    );
    await AppSettings.shareOnlineStatus.setItem(true);
    await AppSettings.appearOffline.setItem(true);
    client.dispose(closeDatabase: true).ignore();
    await firstSync(background: true);
    expect(
      api.requests('/sync').first.url.queryParameters['set_presence'],
      'offline',
    );
  });
}
