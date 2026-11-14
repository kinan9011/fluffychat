// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_quarantine_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
  });

  test('there is no notice by default', () {
    expect(hasDatabaseQuarantineNotice, isFalse);
  });

  test('a quarantine sets the notice for that client', () async {
    await markDatabaseQuarantined('a');

    expect(hasDatabaseQuarantineNotice, isTrue);
    expect(AppSettings.databaseQuarantinedClients.value, ['a']);
  });

  test('the same client is not listed twice', () async {
    await markDatabaseQuarantined('a');
    await markDatabaseQuarantined('a');
    await markDatabaseQuarantined('b');

    expect(AppSettings.databaseQuarantinedClients.value, ['a', 'b']);
  });

  test('dismissing removes the notice and it stays gone', () async {
    await markDatabaseQuarantined('a');

    await dismissDatabaseQuarantineNotice();

    expect(hasDatabaseQuarantineNotice, isFalse);
    expect(AppSettings.databaseQuarantinedClients.value, isEmpty);
  });

  test('a new quarantine after a dismissal shows the notice again', () async {
    await markDatabaseQuarantined('a');
    await dismissDatabaseQuarantineNotice();

    await markDatabaseQuarantined('a');

    expect(hasDatabaseQuarantineNotice, isTrue);
  });

  test('the notice state cannot be set from a config file', () {
    expect(
      filterPlatformConfiguration({
        'databaseQuarantinedClients': <String>[],
      }, PlatformConfigSource.mdm),
      isEmpty,
    );
    expect(
      filterPlatformConfiguration({
        'databaseQuarantinedClients': <String>[],
      }, PlatformConfigSource.web),
      isEmpty,
    );
  });
}
