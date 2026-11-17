// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:matrix/matrix.dart';

/// The "default disappearing timer" of the privacy settings. It is only put
/// into the creation request of a chat the user starts now: existing chats,
/// chats other people create and spaces are never touched.
abstract class DefaultRetention {
  static final allowedSeconds = <int>[
    0,
    for (final preset in RetentionPolicy.presets) preset.inSeconds,
  ];

  static int normalize(int seconds) =>
      allowedSeconds.contains(seconds) ? seconds : 0;

  /// Looks the server up only when a timer is set, so chat creation is not
  /// delayed for everybody else. The SDK adds the encryption state to the list
  /// it is given, so the list must stay growable.
  static Future<List<StateEvent>> initialStateFor(
    ServerCapabilitiesService capabilities,
    Client client,
  ) async {
    if (normalize(AppSettings.defaultDisappearSeconds.value) == 0) {
      return <StateEvent>[];
    }
    return initialState(caps: await capabilities.load(client));
  }

  static List<StateEvent> initialState({
    required ServerCapabilities caps,
    int? seconds,
  }) {
    final value = normalize(
      seconds ?? AppSettings.defaultDisappearSeconds.value,
    );
    if (value == 0 || !caps.supports(ServerFeature.retention)) {
      return <StateEvent>[];
    }
    return [
      StateEvent(
        type: RetentionPolicy.eventType,
        content: RetentionPolicy.contentFor(Duration(seconds: value)),
      ),
    ];
  }
}
