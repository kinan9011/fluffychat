// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:collection';

enum FeatureSupport { supported, partial, unsupported, unknown }

enum ServerFeature {
  slidingSync,
  delayedEvents,
  retention,
  qrLogin,
  groupCalls,
  threadNotifications,
  serverSideSearchE2ee,
}

class ServerCapabilityInputs {
  final Object? versionsJson;
  final Object? wellKnownJson;
  final Object? rtcTransportsJson;
  final Object? capabilitiesJson;
  final bool? hasAuthMetadata;
  final bool fallbackLiveKitConfigured;

  bool get isComplete =>
      versionsJson != null && wellKnownJson != null && hasAuthMetadata != null;

  const ServerCapabilityInputs({
    this.versionsJson,
    this.wellKnownJson,
    this.rtcTransportsJson,
    this.capabilitiesJson,
    this.hasAuthMetadata,
    this.fallbackLiveKitConfigured = false,
  });
}

class ServerCapabilities {
  static const maxEntries = 512;
  static const maxStringLength = 4096;
  static const maxDepth = 8;
  static const maxNodes = 5000;

  final Map<ServerFeature, FeatureSupport> features;
  final bool? loginTokenEnabled;

  ServerCapabilities._(
    Map<ServerFeature, FeatureSupport> features,
    this.loginTokenEnabled,
  ) : features = UnmodifiableMapView(Map.of(features));

  static final unknown = ServerCapabilities._({
    for (final feature in ServerFeature.values) feature: FeatureSupport.unknown,
    ServerFeature.serverSideSearchE2ee: FeatureSupport.unsupported,
  }, null);

  ServerCapabilities fillUnknownFrom(ServerCapabilities previous) =>
      ServerCapabilities._({
        for (final feature in ServerFeature.values)
          feature: this[feature] == FeatureSupport.unknown
              ? previous[feature]
              : this[feature],
      }, loginTokenEnabled ?? previous.loginTokenEnabled);

  FeatureSupport operator [](ServerFeature feature) =>
      features[feature] ?? FeatureSupport.unknown;

  bool supports(ServerFeature feature) =>
      this[feature] == FeatureSupport.supported;

  factory ServerCapabilities.derive(ServerCapabilityInputs inputs) {
    final versionsBody = _checked(inputs.versionsJson);
    final versions = _stringList(versionsBody?['versions']);
    final unstable = versions == null
        ? null
        : versionsBody?['unstable_features'] == null
        ? const <String, bool>{}
        : _boolMap(versionsBody?['unstable_features']);
    final known = versions != null && unstable != null;

    final wellKnown = _checked(inputs.wellKnownJson);
    final transports = _checked(inputs.rtcTransportsJson);
    final capabilities = _checked(inputs.capabilitiesJson);

    FeatureSupport flag(String key) => !known
        ? FeatureSupport.unknown
        : unstable[key] == true
        ? FeatureSupport.supported
        : FeatureSupport.unsupported;

    final oidc = inputs.hasAuthMetadata;
    final qrFlag = flag('org.matrix.msc4108');
    final qrLogin = qrFlag != FeatureSupport.supported
        ? qrFlag
        : oidc == null
        ? FeatureSupport.unknown
        : oidc
        ? FeatureSupport.supported
        : FeatureSupport.partial;

    final proxy = _map(wellKnown?['org.matrix.msc3575.proxy']);
    final slidingFlag = flag('org.matrix.simplified_msc3575');
    final slidingSync =
        slidingFlag == FeatureSupport.unsupported && _isWebUrl(proxy?['url'])
        ? FeatureSupport.partial
        : slidingFlag;

    final retentionValue = known ? unstable['org.matrix.msc1763'] : null;
    final retention = !known || retentionValue == null
        ? FeatureSupport.unknown
        : retentionValue
        ? FeatureSupport.supported
        : FeatureSupport.unsupported;

    final threadNotifications = !known
        ? FeatureSupport.unknown
        : versions.any(_isAtLeastV1_4) || unstable['org.matrix.msc3773'] == true
        ? FeatureSupport.supported
        : FeatureSupport.unsupported;

    final groupCalls = _hasLiveKit(wellKnown, transports)
        ? FeatureSupport.supported
        : wellKnown == null && transports == null
        ? FeatureSupport.unknown
        : inputs.fallbackLiveKitConfigured
        ? FeatureSupport.partial
        : FeatureSupport.unsupported;

    final loginToken = _map(capabilities?['m.get_login_token']);
    final enabled = loginToken?['enabled'];

    return ServerCapabilities._({
      ServerFeature.slidingSync: slidingSync,
      ServerFeature.delayedEvents: flag('org.matrix.msc4140'),
      ServerFeature.retention: retention,
      ServerFeature.qrLogin: qrLogin,
      ServerFeature.groupCalls: groupCalls,
      ServerFeature.threadNotifications: threadNotifications,
      ServerFeature.serverSideSearchE2ee: FeatureSupport.unsupported,
    }, enabled is bool ? enabled : null);
  }

  static bool _hasLiveKit(
    Map<String, Object?>? wellKnown,
    Map<String, Object?>? transports,
  ) {
    final foci = wellKnown?['org.matrix.msc4143.rtc_foci'];
    final fociMaps = foci is List ? foci : [foci];
    if (fociMaps.any((f) => _isWebUrl(_map(f)?['livekit_service_url']))) {
      return true;
    }
    final list = transports?['transports'];
    if (list is! List) return false;
    return list.any((t) {
      final map = _map(t);
      return map?['type'] == 'm.livekit' && _isWebUrl(map?['url']);
    });
  }

  static bool _isWebUrl(Object? value) {
    if (value is! String || value.length > maxStringLength) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.isScheme('https') || uri.isScheme('http')) &&
        uri.host.isNotEmpty;
  }

  static final _versionPattern = RegExp(r'^v(\d{1,4})\.(\d{1,4})$');

  static bool _isAtLeastV1_4(String version) {
    final match = _versionPattern.firstMatch(version);
    if (match == null) return false;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > 1 || (major == 1 && minor >= 4);
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    if (value.keys.any((k) => k is! String)) return null;
    return value.cast<String, Object?>();
  }

  static Map<String, Object?>? _checked(Object? json) {
    final root = _map(json);
    if (root == null) return null;
    final stack = <(Object?, int)>[(root, 0)];
    var nodes = 0;
    while (stack.isNotEmpty) {
      final (value, depth) = stack.removeLast();
      if (++nodes > maxNodes || depth > maxDepth) return null;
      if (value is String) {
        if (value.length > maxStringLength) return null;
      } else if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key;
          if (key is! String || key.length > maxStringLength) return null;
          stack.add((entry.value, depth + 1));
        }
      } else if (value is List) {
        for (final item in value) {
          stack.add((item, depth + 1));
        }
      } else if (value is double) {
        if (!value.isFinite) return null;
      } else if (value != null && value is! num && value is! bool) {
        return null;
      }
    }
    return root;
  }

  static List<String>? _stringList(Object? value) {
    if (value is! List || value.length > maxEntries) return null;
    if (value.any((v) => v is! String)) return null;
    return value.cast<String>();
  }

  static Map<String, bool>? _boolMap(Object? value) {
    final map = _map(value);
    if (map == null || map.length > maxEntries) return null;
    if (map.values.any((v) => v is! bool)) return null;
    return map.cast<String, bool>();
  }
}
