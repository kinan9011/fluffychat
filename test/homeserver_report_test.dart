// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart' show Locale, StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/server_capabilities/homeserver_report.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';

ServerCapabilities _caps(Map<String, bool> unstable, {bool? oidc}) =>
    ServerCapabilities.derive(
      ServerCapabilityInputs(
        versionsJson: {
          'versions': ['v1.1'],
          'unstable_features': unstable,
        },
        wellKnownJson: const {},
        hasAuthMetadata: oidc ?? false,
      ),
    );

void main() {
  late L10n l10n;

  setUpAll(() async => l10n = await L10n.delegate.load(const Locale('en')));

  group('buildAdminReport', () {
    test('names the server, the limit and one line per feature', () {
      final report = buildAdminReport(
        info: const HomeserverInfo(
          domain: 'example.org',
          software: 'Synapse',
          version: '1.99.0',
          uploadLimitBytes: 104857600,
        ),
        caps: _caps({
          'org.matrix.simplified_msc3575': true,
          'org.matrix.msc1763': false,
        }),
        appName: 'FluffyChat',
        l10n: l10n,
      );
      expect(report, contains('example.org'));
      expect(report, contains('Synapse 1.99.0'));
      expect(report, contains('upload limit 104.9 MB'));
      for (final feature in homeserverFeatureOrder) {
        expect(report, contains('${featureTitle(l10n, feature)}: '));
      }
      expect(report, contains('Sliding sync: Supported'));
      expect(report, contains('Disappearing messages: Not set up'));
      expect(report, contains('Created with FluffyChat'));
    });

    test('contains nothing about the user, their device or tokens', () {
      const secrets = [
        '@alice:example.org',
        'alice',
        'DEVICEID1234',
        'syt_secret_token',
        '192.0.2.77',
      ];
      final report = buildAdminReport(
        info: const HomeserverInfo(domain: 'example.org'),
        caps: _caps(const {}),
        appName: 'FluffyChat',
        l10n: l10n,
      );
      for (final secret in secrets) {
        expect(report, isNot(contains(secret)));
      }
    });

    test('all four states read differently', () {
      final labels = {
        for (final s in FeatureSupport.values) supportLabel(l10n, s),
      };
      expect(labels, hasLength(4));
    });

    test('hostile software strings are cleaned and cut', () {
      final report = buildAdminReport(
        info: HomeserverInfo(
          domain: 'example.org',
          software: 'Evil\u202E\u0000Server\n${'x' * 500}',
          version: '1\u2066.0',
        ),
        caps: _caps(const {}),
        appName: 'App\u202E',
        l10n: l10n,
      );
      expect(report, isNot(contains('\u202E')));
      expect(report, isNot(contains('\u0000')));
      expect(report, isNot(contains('\u2066')));
      for (final line in report.split('\n')) {
        expect(line.characters.length, lessThan(200));
      }
    });
  });

  group('formatUploadLimit', () {
    test('null, zero, negative and absurd values give nothing', () {
      expect(formatUploadLimit(null), isNull);
      expect(formatUploadLimit(0), isNull);
      expect(formatUploadLimit(-1), isNull);
      expect(formatUploadLimit(1 << 62), isNull);
      expect(formatUploadLimit((1 << 40) + 1), isNull);
    });

    test('readable sizes', () {
      expect(formatUploadLimit(1), '0 KB');
      expect(formatUploadLimit(1500), '1.5 KB');
      expect(formatUploadLimit(100 * 1000 * 1000), '100 MB');
      expect(formatUploadLimit(104857600), '104.9 MB');
      expect(formatUploadLimit(2 * 1000 * 1000 * 1000), '2 GB');
    });
  });

  group('parseServerVersion', () {
    test('a valid answer', () {
      final parsed = parseServerVersion({
        'server': {'name': 'Synapse', 'version': '1.99.0'},
      });
      expect(parsed?.name, 'Synapse');
      expect(parsed?.version, '1.99.0');
    });

    test('anything else is ignored without throwing', () {
      for (final bad in <Object?>[
        null,
        'x',
        5,
        <Object?>[],
        {},
        {'server': 'x'},
        {'server': {}},
        {
          'server': {'name': 5, 'version': '1'},
        },
        {
          'server': {'name': 'a', 'version': null},
        },
        {
          'server': {'name': 'a' * 300, 'version': '1'},
        },
        {
          'server': {'name': 'a', 'version': 'v' * 300},
        },
        {
          'server': {'name': '   ', 'version': '1'},
        },
      ]) {
        expect(parseServerVersion(bad), isNull, reason: '$bad');
      }
    });

    test('control characters in the strings are removed', () {
      final parsed = parseServerVersion({
        'server': {'name': 'Syn\u0000apse', 'version': '1\n.0'},
      });
      expect(parsed?.name, 'Syn apse');
      expect(parsed?.version, '1 .0');
    });
  });

  group('isTrustedFederationHost', () {
    bool trust(String host, {String? hs}) => isTrustedFederationHost(
      host,
      userDomain: 'example.org',
      homeserverHost: hs,
    );

    test('the domain, its subdomains and the homeserver host', () {
      expect(trust('example.org'), isTrue);
      expect(trust('Matrix.Example.ORG'), isTrue);
      expect(trust('a.b.example.org'), isTrue);
      expect(trust('matrix.provider.net', hs: 'matrix.provider.net'), isTrue);
      expect(trust('x.matrix.provider.net', hs: 'matrix.provider.net'), isTrue);
    });

    test('lookalikes and other machines are refused', () {
      expect(trust('evilexample.org'), isFalse);
      expect(trust('example.org.evil.net'), isFalse);
      expect(trust('evil.net'), isFalse);
      expect(trust('192.168.1.1'), isFalse);
      expect(trust('localhost'), isFalse);
      expect(trust(''), isFalse);
      expect(trust('a' * 300), isFalse);
    });
  });
}
