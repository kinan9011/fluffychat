// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/secure_storage.dart';

void main() {
  test('the Android plugin never deletes stored data on an error', () {
    expect(createSecureStorage().aOptions.params['resetOnError'], 'false');
  });

  test('only the confirmed reset can use the repairing storage', () {
    expect(
      createRepairingSecureStorage().aOptions.params['resetOnError'],
      'true',
    );
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => f.readAsStringSync().contains('createRepairingSecureStorage('),
        )
        .map((f) => f.path)
        .toSet();
    expect(offenders, {
      'lib/utils/secure_storage.dart',
      'lib/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/account_secret_purge.dart',
    });
  });

  test('a custom iOS option is kept', () {
    const options = IOSOptions(groupId: 'group.test');
    expect(
      createSecureStorage(iOptions: options).iOptions.params['groupId'],
      'group.test',
    );
  });

  test('every secure storage in the app comes from createSecureStorage', () {
    final direct = RegExp(r'\bFlutterSecureStorage\s*\(');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.path != 'lib/utils/secure_storage.dart')
        .where((f) => direct.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
