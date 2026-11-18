// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/app_temp_directory.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/safe_init_client.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/environment_constants.dart';
import '../utils/fluffy_chat_tester.dart';

Future<void> finalLogout(WidgetTester widgetTester) async {
  final tester = await widgetTester.startFluffyChatTest();
  await tester.ensureLoggedIn();
  final clients = tester.tester
      .state<MatrixState>(find.byType(Matrix))
      .widget
      .clients;
  expect(clients, isNotEmpty);
  expect(clients.every((client) => client is SafeInitClient), isTrue);

  final tempDir = await appTempDirectory();
  File(p.join(tempDir.path, 'probe')).writeAsStringSync('decrypted media');
  await tester.logout();

  final leftover = Directory(
    p.join((await getTemporaryDirectory()).path, appTempDirName),
  );
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (leftover.existsSync() && DateTime.now().isBefore(end)) {
    await tester.tester.pump(const Duration(milliseconds: 500));
  }
  expect(leftover.existsSync(), isFalse);
}

extension AuthFlows on FluffyChatTester {
  Future<void> initCryptoIdentity({String username = user1Name}) async {
    final passphrase = userPassphrases[username];
    if (passphrase != null) {
      await waitFor('Restore Crypto Identity');
      await enterText(TextField, passphrase);
      await tapOn('Unlock');
    } else {
      await waitFor('Set Up Crypto Identity');
      await enterText(TextField, passphrase1, index: 0);
      await enterText(TextField, passphrase1, index: 1);
      await tapOn('Continue');
      await tapOn('Continue');
      userPassphrases[username] = passphrase1;
    }
  }

  Future<void> login({
    String username = user1Name,
    String password = user1Pw,
  }) async {
    await waitFor('Sign in');
    await tapOn('Sign in');
    await enterText(TextField, 'http://$homeserver', index: 0);
    await tapOn(RadioListTile<PublicHomeserverData>, index: 0);
    await tapOn('Continue');
    await waitFor('Log in to http://$homeserver');
    await enterText(TextField, username, index: 0);
    await enterText(TextField, password, index: 1);
    await tapOn('Login');
  }

  Future<void> logout() async {
    await ensureLoggedIn();
    await tapOn(Key('accounts_and_settings_buttons'));
    await tapOn(find.widgetWithText(PopupMenuItem<Object>, 'Settings'));
    await scrollUntilVisible('Logout');
    await tapOn('Logout');
    await tapOn(Key('ok_cancel_alert_dialog_ok_button'));
    await waitFor('Sign in');
  }

  Future<void> skipNoNotificationsDialog() async {
    if (await isVisible('Push notifications not available')) {
      await tapOn('Do not show again');
    }
  }

  static final Map<String, String> userPassphrases = {};

  Future<bool> ensureLoggedIn() async {
    if (await isVisible('Sign in') == false) return false;

    await login();
    await initCryptoIdentity();

    await skipNoNotificationsDialog();
    return true;
  }
}
