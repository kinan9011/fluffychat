// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

/// What the background fetch mode (no GUI) tells the server about presence.
const backgroundFetchPresence = PresenceType.offline;

/// Whether other people may see this user as online. Hidden is the default:
/// the user has to opt in to share it.
class PresencePolicy {
  const PresencePolicy({
    required this.shareOnlineStatus,
    required this.appearOffline,
    this.away = false,
  });

  factory PresencePolicy.fromSettings() => PresencePolicy(
    shareOnlineStatus: AppSettings.shareOnlineStatus.value,
    appearOffline: AppSettings.appearOffline.value,
    away: AppSettings.presenceAway.value,
  );

  final bool shareOnlineStatus;
  final bool appearOffline;

  /// The user chose "Away". Only matters while visible: a hidden user stays
  /// offline whatever else is set.
  final bool away;

  bool get visibleToOthers => shareOnlineStatus && !appearOffline;

  /// The `set_presence` of the sync request. Null lets the server mark the
  /// user online, which is only ever allowed when the user shares it.
  PresenceType? syncPresence({required bool foreground}) {
    if (!visibleToOthers) return PresenceType.offline;
    if (away) return PresenceType.unavailable;
    return foreground ? null : PresenceType.unavailable;
  }

  /// The presence to publish together with a status message.
  PresenceType get statusPresence {
    if (!visibleToOthers) return PresenceType.offline;
    return away ? PresenceType.unavailable : PresenceType.online;
  }
}

/// The only writer of [Client.syncPresence] (besides the background fetch
/// mode) and of the presence status.
class PresenceApplier {
  static final _announced = Expando<bool>('presenceOfflineAnnounced');

  /// Sets the sync presence of every client. While hidden, each client also
  /// tells the server once that it is offline, because a sync request alone
  /// does not clear a presence the server already holds.
  static Future<void> apply(
    Iterable<Client> clients, {
    required bool foreground,
    PresencePolicy? policy,
  }) async {
    policy ??= PresencePolicy.fromSettings();
    final all = clients.toList();
    for (final client in all) {
      client.syncPresence = policy.syncPresence(foreground: foreground);
    }
    for (final client in all) {
      if (policy.visibleToOthers) {
        _announced[client] = false;
        continue;
      }
      if (_announced[client] == true) continue;
      final userId = client.userID;
      if (!client.isLogged() || userId == null) continue;
      _announced[client] = true;
      try {
        await client.setPresence(userId, PresenceType.offline);
      } on MatrixException {
        Logs().w('[Presence] the server refused the offline status');
      } catch (_) {
        _announced[client] = false;
        Logs().w('[Presence] could not announce offline');
      }
    }
  }
}
