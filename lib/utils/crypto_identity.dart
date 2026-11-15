// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// `null` when encryption is off or the client is not logged in.
Future<bool?> defaultLoadCryptoIdentityConnected(Client client) async {
  if (!client.encryptionEnabled || !client.isLogged()) return null;
  await client.accountDataLoading;
  await client.userDeviceKeysLoading;
  if (client.prevBatch == null) await client.onSync.stream.first;
  final state = await client.getCryptoIdentityState();
  return state.initialized && state.connected;
}

@visibleForTesting
Future<bool?> Function(Client client) loadCryptoIdentityConnected =
    defaultLoadCryptoIdentityConnected;

Future<bool?> cryptoIdentityConnected(Client client) =>
    loadCryptoIdentityConnected(client);

/// Bumped when the key backup page closes: whoever shows the backup state
/// checks it again then, and only then.
final ValueNotifier<int> cryptoIdentityRevision = ValueNotifier(0);
