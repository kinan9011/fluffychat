// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Android plugin never deletes stored data on an error', () {
    expect(createSecureStorage().aOptions.params['resetOnError'], 'false');
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
