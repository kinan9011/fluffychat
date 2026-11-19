// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' show BaseClient;
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/crypto_identity.dart' as crypto_identity;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'set_up_vodozemac.dart';

// key @test:fakeServer.notExisting
const pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

class _FakeNotifications extends FlutterLocalNotificationsPlatform {}

/// Fake clients have no key backup state worth showing: no banner in tests
/// unless a test brings its own answer.
Future<bool?> noCryptoIdentity(Client client) async => null;

/// More than one test client needs its own database and its own name.
Future<Client> prepareTestClient({
  bool loggedIn = false,
  Uri? homeserver,
  String id = 'FluffyChat Widget Test',
  String? clientName,
  BaseClient? httpClient,
  bool waitForFirstSync = true,
}) async {
  await setUpVodozemac();
  SharedPreferences.setMockInitialValues({});
  FlutterLocalNotificationsPlatform.instance = _FakeNotifications();
  await AppSettings.init(loadWebConfigFile: false);
  crypto_identity.loadCryptoIdentityConnected = noCryptoIdentity;

  homeserver ??= Uri.parse('https://fakeserver.notexisting');
  final client = Client(
    clientName ?? 'FluffyChat Widget Tests',
    httpClient: httpClient ?? FakeMatrixApi(),
    verificationMethods: {
      KeyVerificationMethod.numbers,
      KeyVerificationMethod.emoji,
    },
    importantStateEvents: <String>{
      'im.ponies.room_emotes', // we want emotes to work properly
    },
    database: await MatrixSdkDatabase.init(
      clientName ?? 'test',
      database: await databaseFactoryFfi.openDatabase(
        ':memory:',
        options: OpenDatabaseOptions(singleInstance: clientName == null),
      ),
      sqfliteFactory: databaseFactoryFfi,
    ),
    supportedLoginTypes: {
      AuthenticationTypes.password,
      AuthenticationTypes.sso,
    },
  );
  client.backgroundSync = waitForFirstSync;
  await client.init(
    waitForFirstSync: waitForFirstSync,
    newHomeserver: Uri.parse('https://fakeServer.notExisting'),
    newDeviceID: 'ABCD1234',
    newDeviceName: 'Screenshot Tester',
    newToken: '1234',
    newUserID: '@test:fakeServer.notExisting',
    newOlmAccount: pickledOlmAccount,
  );
  return client;
}
