// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:matrix/matrix.dart';

/// Answers the capability request of the real app like a homeserver with or
/// without a LiveKit service, per client, changeable at any time.
class FakeCallCapabilities {
  final Set<Client> supported = Set.identity();
  final Set<Client> offline = Set.identity();
  final bool defaultSupported;

  /// Answers without asking the SDK client at all (no database isolate, no
  /// timers): for tests that pump on the fake clock.
  final bool pure;

  FakeCallCapabilities({this.defaultSupported = true, this.pure = false});

  final Map<Client, bool> _overrides = Map.identity();

  void set(Client client, {required bool supported}) =>
      _overrides[client] = supported;

  ServerCapabilitySource sourceFor(Client client) => _Source(
    pure ? null : SdkServerCapabilitySource(client),
    () => _overrides[client] ?? defaultSupported,
    () => offline.contains(client),
  );

  /// Installs the fake for every `Matrix` created from now on.
  void install() => MatrixState.capabilitySourceFor = sourceFor;

  static void uninstall() => MatrixState.capabilitySourceFor = null;
}

/// The real source of the SDK client (so tests that stub the homeserver keep
/// working), with the call service of the fake server added or left out.
class _Source implements ServerCapabilitySource {
  final ServerCapabilitySource? real;
  final bool Function() supported;
  final bool Function() offline;

  _Source(this.real, this.supported, this.offline);

  static const _foci = {
    'org.matrix.msc4143.rtc_foci': [
      {'type': 'livekit', 'livekit_service_url': 'https://lk.example'},
    ],
  };

  @override
  Future<ServerCapabilityInputs> fetch() async {
    if (offline()) throw const ServerCapabilitiesUnavailable();
    final inputs =
        await real?.fetch() ??
        const ServerCapabilityInputs(
          versionsJson: {
            'versions': ['v1.1'],
          },
          wellKnownJson: <String, Object?>{},
          hasAuthMetadata: false,
        );
    if (!supported()) return inputs;
    final wellKnown = inputs.wellKnownJson;
    return ServerCapabilityInputs(
      versionsJson: inputs.versionsJson,
      wellKnownJson: {
        if (wellKnown is Map<String, Object?>) ...wellKnown,
        ..._foci,
      },
      rtcTransportsJson: inputs.rtcTransportsJson,
      capabilitiesJson: inputs.capabilitiesJson,
      hasAuthMetadata: inputs.hasAuthMetadata,
      fallbackLiveKitConfigured: inputs.fallbackLiveKitConfigured,
    );
  }
}
