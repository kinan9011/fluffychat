// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

const _synapseVersions = <String, Object?>{
  'versions': ['r0.6.1', 'v1.1', 'v1.4', 'v1.10', 'v1.12'],
  'unstable_features': {
    'org.matrix.msc3773': true,
    'org.matrix.msc4140': true,
    'org.matrix.simplified_msc3575': true,
    'org.matrix.msc4108': true,
    'org.matrix.msc2285.stable': true,
    'org.matrix.msc3881': false,
  },
};

const _synapseWellKnown = <String, Object?>{
  'm.homeserver': {'base_url': 'https://matrix.example.org'},
  'org.matrix.msc4143.rtc_foci': [
    {'type': 'livekit', 'livekit_service_url': 'https://lk.example.org'},
  ],
};

const _tuwunelVersions = <String, Object?>{
  'versions': ['r0.5.0', 'v1.1', 'v1.5', 'v1.11'],
  'unstable_features': {'org.matrix.e2e_cross_signing': true},
};

ServerCapabilities derive({
  Object? versions,
  Object? wellKnown,
  Object? transports,
  Object? capabilities,
  bool? authMetadata,
  bool fallbackLiveKit = false,
}) => ServerCapabilities.derive(
  ServerCapabilityInputs(
    versionsJson: versions,
    wellKnownJson: wellKnown,
    rtcTransportsJson: transports,
    capabilitiesJson: capabilities,
    hasAuthMetadata: authMetadata,
    fallbackLiveKitConfigured: fallbackLiveKit,
  ),
);

void main() {
  group('Synapse-like server', () {
    final caps = derive(
      versions: _synapseVersions,
      wellKnown: _synapseWellKnown,
      authMetadata: true,
      capabilities: {
        'm.get_login_token': {'enabled': true},
      },
    );

    test('supported features', () {
      expect(caps[ServerFeature.slidingSync], FeatureSupport.supported);
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.supported);
      expect(caps[ServerFeature.qrLogin], FeatureSupport.supported);
      expect(caps[ServerFeature.groupCalls], FeatureSupport.supported);
      expect(caps[ServerFeature.threadNotifications], FeatureSupport.supported);
      expect(caps.loginTokenEnabled, isTrue);
    });

    test('retention has no flag, so it is unknown, not unsupported', () {
      expect(caps[ServerFeature.retention], FeatureSupport.unknown);
    });

    test('server side search in encrypted rooms is never supported', () {
      expect(
        caps[ServerFeature.serverSideSearchE2ee],
        FeatureSupport.unsupported,
      );
    });

    test('every feature has a value', () {
      for (final feature in ServerFeature.values) {
        expect(caps.features.containsKey(feature), isTrue, reason: '$feature');
      }
    });
  });

  group('tuwunel-like server', () {
    final caps = derive(
      versions: _tuwunelVersions,
      wellKnown: {
        'm.homeserver': {'base_url': 'https://t.example.org'},
      },
      authMetadata: false,
    );

    test('unsupported features', () {
      expect(caps[ServerFeature.slidingSync], FeatureSupport.unsupported);
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.unsupported);
      expect(caps[ServerFeature.qrLogin], FeatureSupport.unsupported);
      expect(caps[ServerFeature.groupCalls], FeatureSupport.unsupported);
    });

    test('thread notifications follow the spec version', () {
      expect(caps[ServerFeature.threadNotifications], FeatureSupport.supported);
      final old = derive(
        versions: {
          'versions': ['r0.6.1', 'v1.3'],
        },
      );
      expect(
        old[ServerFeature.threadNotifications],
        FeatureSupport.unsupported,
      );
    });
  });

  group('partial', () {
    test('QR sign-in flag without OIDC', () {
      final caps = derive(
        versions: _synapseVersions,
        authMetadata: false,
        wellKnown: const <String, Object?>{},
      );
      expect(caps[ServerFeature.qrLogin], FeatureSupport.partial);
    });

    test('sliding sync only through a proxy', () {
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: {
          'org.matrix.msc3575.proxy': {'url': 'https://proxy.example.org'},
        },
      );
      expect(caps[ServerFeature.slidingSync], FeatureSupport.partial);
    });

    test('QR sign-in flag with unknown auth metadata stays unknown', () {
      final caps = derive(
        versions: _synapseVersions,
        wellKnown: const <String, Object?>{},
      );
      expect(caps[ServerFeature.qrLogin], FeatureSupport.unknown);
    });

    test('group calls with only the configured fallback LiveKit', () {
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: const <String, Object?>{},
        fallbackLiveKit: true,
      );
      expect(caps[ServerFeature.groupCalls], FeatureSupport.partial);
    });
  });

  group('group calls sources', () {
    test('transports endpoint', () {
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: const <String, Object?>{},
        transports: {
          'transports': [
            {'type': 'm.livekit', 'url': 'https://lk.example.org'},
          ],
        },
      );
      expect(caps[ServerFeature.groupCalls], FeatureSupport.supported);
    });

    test('Famedly style single focus map', () {
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: {
          'org.matrix.msc4143.rtc_foci': {
            'livekit_service_url': 'https://lk.example.org',
          },
        },
      );
      expect(caps[ServerFeature.groupCalls], FeatureSupport.supported);
    });

    test('junk foci and non web schemes do not count', () {
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: {
          'org.matrix.msc4143.rtc_foci': [
            {'livekit_service_url': 'javascript:alert(1)'},
            {'livekit_service_url': 'ftp://lk.example.org'},
            {'livekit_service_url': 42},
            'string',
            null,
          ],
        },
      );
      expect(caps[ServerFeature.groupCalls], FeatureSupport.unsupported);
    });

    test('plain http counts, like in the call code', () {
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: {
          'org.matrix.msc4143.rtc_foci': [
            {'livekit_service_url': 'http://localhost:7880'},
          ],
        },
      );
      expect(caps[ServerFeature.groupCalls], FeatureSupport.supported);
    });
  });

  group('empty and unreachable', () {
    test('everything failed: all unknown except the constant', () {
      final caps = derive();
      for (final feature in ServerFeature.values) {
        if (feature == ServerFeature.serverSideSearchE2ee) continue;
        expect(caps[feature], FeatureSupport.unknown, reason: '$feature');
      }
      expect(caps.loginTokenEnabled, isNull);
    });

    test('empty /versions object is malformed (versions is required)', () {
      final caps = derive(versions: const <String, Object?>{});
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.unknown);
    });

    test('no unstable_features means unsupported', () {
      final caps = derive(
        versions: {
          'versions': ['v1.1'],
        },
      );
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.unsupported);
      expect(caps[ServerFeature.slidingSync], FeatureSupport.unsupported);
    });
  });

  group('malformed input never throws and never claims support', () {
    final cases = <String, Map<String, Object?>>{
      'versions is a string': {'versions': 'v1.1'},
      'versions of numbers': {
        'versions': [1, 2, 3],
      },
      'unstable_features is a list': {
        'versions': ['v1.1'],
        'unstable_features': ['org.matrix.msc4140'],
      },
      'unstable_features with string values': {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc4140': 'true'},
      },
      'unstable_features with int values': {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc4140': 1},
      },
      'null versions': {'versions': null},
    };
    cases.forEach((name, json) {
      test(name, () {
        final caps = derive(versions: json, wellKnown: json, transports: json);
        expect(
          caps[ServerFeature.delayedEvents],
          isNot(FeatureSupport.supported),
        );
        expect(
          caps[ServerFeature.slidingSync],
          isNot(FeatureSupport.supported),
        );
        expect(caps[ServerFeature.qrLogin], isNot(FeatureSupport.supported));
        expect(caps[ServerFeature.groupCalls], isNot(FeatureSupport.supported));
      });
    });

    test('top level values of the wrong type', () {
      for (final junk in <Object?>[
        'x',
        1,
        1.5,
        true,
        <Object?>[],
        <Object?, Object?>{1: 2},
        double.nan,
      ]) {
        final caps = derive(
          versions: junk,
          wellKnown: junk,
          transports: junk,
          capabilities: junk,
        );
        expect(caps[ServerFeature.slidingSync], FeatureSupport.unknown);
        expect(caps.loginTokenEnabled, isNull);
      }
    });

    test('capabilities with a non bool enabled flag', () {
      final caps = derive(
        capabilities: {
          'm.get_login_token': {'enabled': 'yes'},
        },
      );
      expect(caps.loginTokenEnabled, isNull);
    });
  });

  group('oversized and hostile input', () {
    test('100k unstable_features entries is rejected as a whole', () {
      final huge = <String, Object?>{
        for (var i = 0; i < 100000; i++) 'org.example.f$i': true,
      };
      huge['org.matrix.msc4140'] = true;
      final caps = derive(
        versions: {
          'versions': ['v1.1'],
          'unstable_features': huge,
        },
      );
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.unknown);
    });

    test('1 MB strings are rejected', () {
      final big = 'a' * (1 << 20);
      final caps = derive(
        versions: {
          'versions': ['v1.1', big],
          'unstable_features': {'org.matrix.msc4140': true},
        },
        wellKnown: {
          'org.matrix.msc4143.rtc_foci': [
            {'livekit_service_url': 'https://$big'},
          ],
        },
      );
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.unknown);
      expect(caps[ServerFeature.groupCalls], isNot(FeatureSupport.supported));
    });

    test('very deep nesting in well-known does not overflow the stack', () {
      Object? nested = 'leaf';
      for (var i = 0; i < 20000; i++) {
        nested = <String, Object?>{'a': nested};
      }
      final caps = derive(
        versions: _tuwunelVersions,
        wellKnown: {'org.matrix.msc4143.rtc_foci': nested},
        capabilities: nested,
      );
      expect(caps[ServerFeature.groupCalls], isNot(FeatureSupport.supported));
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.unsupported);
    });

    test('wide well-known (200k keys) is rejected', () {
      final wide = <String, Object?>{
        for (var i = 0; i < 200000; i++) 'k$i': 'v',
      };
      wide['org.matrix.msc4143.rtc_foci'] = [
        {'livekit_service_url': 'https://lk.example.org'},
      ];
      final caps = derive(versions: _tuwunelVersions, wellKnown: wide);
      expect(caps[ServerFeature.groupCalls], isNot(FeatureSupport.supported));
    });

    test('prototype-pollution style keys are plain data', () {
      final caps = derive(
        versions: {
          'versions': ['v1.1'],
          'unstable_features': {
            '__proto__': true,
            'constructor': true,
            'org.matrix.msc4140': true,
          },
        },
      );
      expect(caps[ServerFeature.delayedEvents], FeatureSupport.supported);
    });
  });

  group('merging with an earlier answer', () {
    test('unknown keeps the earlier value, known wins', () {
      final earlier = derive(
        versions: _synapseVersions,
        wellKnown: _synapseWellKnown,
        authMetadata: true,
        capabilities: {
          'm.get_login_token': {'enabled': true},
        },
      );
      final now = derive(wellKnown: const <String, Object?>{});
      final merged = now.fillUnknownFrom(earlier);
      expect(merged[ServerFeature.delayedEvents], FeatureSupport.supported);
      expect(merged[ServerFeature.qrLogin], FeatureSupport.supported);
      expect(merged[ServerFeature.groupCalls], FeatureSupport.unsupported);
      expect(merged.loginTokenEnabled, isTrue);
    });
  });

  test('inputs are complete only when every deciding source answered', () {
    const full = ServerCapabilityInputs(
      versionsJson: {},
      wellKnownJson: {},
      hasAuthMetadata: false,
    );
    expect(full.isComplete, isTrue);
    expect(
      const ServerCapabilityInputs(
        versionsJson: {},
        hasAuthMetadata: true,
      ).isComplete,
      isFalse,
    );
    expect(const ServerCapabilityInputs().isComplete, isFalse);
  });

  group('fail closed', () {
    final caps = derive(
      versions: _synapseVersions,
      wellKnown: _synapseWellKnown,
      authMetadata: true,
    );

    test('supports is true only for supported', () {
      expect(caps.supports(ServerFeature.delayedEvents), isTrue);
      expect(caps.supports(ServerFeature.retention), isFalse);
      expect(caps.supports(ServerFeature.serverSideSearchE2ee), isFalse);
      expect(
        ServerCapabilities.unknown.supports(ServerFeature.slidingSync),
        isFalse,
      );
    });

    test('the feature map cannot be modified by callers', () {
      expect(
        () => caps.features[ServerFeature.retention] = FeatureSupport.supported,
        throwsUnsupportedError,
      );
    });
  });
}
