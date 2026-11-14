// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';

bool get hasDatabaseQuarantineNotice =>
    AppSettings.databaseQuarantinedClients.value.isNotEmpty;

Future<void> markDatabaseQuarantined(String clientName) async {
  final names = AppSettings.databaseQuarantinedClients.value;
  if (names.contains(clientName)) return;
  await AppSettings.databaseQuarantinedClients.setItem([...names, clientName]);
}

Future<void> dismissDatabaseQuarantineNotice() =>
    AppSettings.databaseQuarantinedClients.setItem([]);
