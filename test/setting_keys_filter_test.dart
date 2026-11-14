// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterPlatformConfiguration (web config.json)', () {
    Map<String, Object?> web(Map<String, Object?> config) =>
        filterPlatformConfiguration(config, PlatformConfigSource.web);

    test('branding keys keep working', () {
      final config = <String, Object?>{
        'applicationName': 'Acme Chat',
        'defaultHomeserver': 'matrix.example.org',
        'presetHomeserver': 'matrix.example.org',
        'welcomeText': 'Hi',
        'website': 'https://example.org',
        'logoUrl': 'https://example.org/logo.png',
        'privacyPolicy': 'https://example.org/privacy',
        'tos': 'https://example.org/tos',
        'colorSchemeSeedInt': 4283835834,
        'enableMatrixNativeOIDC': false,
        'enableSoftLogout': true,
      };
      expect(web(config), config);
    });

    test('security sensitive keys are dropped', () {
      final result = web({
        'pushNotificationsGatewayUrl': 'https://evil.example/notify',
        'pushNotificationsPusherFormat': 'full',
        'fallbackLiveKitInstance': 'https://evil.example/sfu',
        'unifiedPushEndpoint': 'https://evil.example/up',
        'unifiedPushRegistered': true,
        'noEncryptionWarningShown': true,
        'databaseUnencryptedClients': ['x'],
        'databaseUnencryptedNoticeDismissed': true,
        'knownErrorHashes': ['x'],
        'lastUpdateCheckDate': '2999-01-01',
        'applicationName': 'Kept',
      });
      expect(result, {'applicationName': 'Kept'});
    });

    test('privacy toggles can only be tightened', () {
      expect(
        web({
          'sendTypingNotifications': true,
          'sendPublicReadReceipts': true,
          'autoSendErrorReports': true,
        }),
        isEmpty,
      );
      final tightened = {
        'sendTypingNotifications': false,
        'sendPublicReadReceipts': false,
        'autoSendErrorReports': false,
      };
      expect(web(tightened), tightened);
    });

    test('shareKeysWith accepts only valid values stricter than all', () {
      expect(web({'shareKeysWith': 'all'}), isEmpty);
      expect(web({'shareKeysWith': 'nonsense'}), isEmpty);
      expect(web({'shareKeysWith': 5}), isEmpty);
      expect(web({'shareKeysWith': 'crossVerified'}), {
        'shareKeysWith': 'crossVerified',
      });
    });

    test('links opened by the app must be https', () {
      expect(
        web({
          'website': 'file:///etc/passwd',
          'privacyPolicy': 'javascript:alert(1)',
          'tos': 'http://example.org/tos',
          'logoUrl': 42,
        }),
        isEmpty,
      );
      final https = {
        'website': 'https://example.org',
        'privacyPolicy': 'https://example.org/privacy',
        'tos': 'https://example.org/tos',
        'logoUrl': 'https://example.org/logo.png',
      };
      expect(web(https), https);
    });

    test('keys are matched case sensitively', () {
      expect(
        web({
          'ShareKeysWith': 'crossVerified',
          'APPLICATIONNAME': 'x',
          'PushNotificationsGatewayUrl': 'https://evil.example',
        }),
        isEmpty,
      );
    });

    test('calls can be switched off by the deployer, default is on', () {
      expect(web({'callsEnabled': false}), {'callsEnabled': false});
      expect(AppSettings.callsEnabled.defaultValue, isTrue);
    });

    group('numeric settings are range checked', () {
      const kept = <String, List<Object>>{
        'fontSizeFactor': [1.5, 0.5, 3.0],
        'textMessageMaxLength': [16384, 1, 65536],
        'messagePreviewMaxLines': [0, 500],
        'sendTimelineEventTimeout': [5, 120],
        'audioRecordingNumChannels': [1, 2],
        'audioRecordingBitRate': [64000, 6000, 510000],
        'audioRecordingSamplingRate': [48000, 8000],
      };
      const dropped = <String, List<Object>>{
        'fontSizeFactor': [1000.0, 0.1, 1, double.nan, double.infinity, '1.0'],
        'textMessageMaxLength': [-1, 0, 65537, '100'],
        'messagePreviewMaxLines': [-5, 501],
        'sendTimelineEventTimeout': [0, 4, 121],
        'audioRecordingNumChannels': [0, 3],
        'audioRecordingBitRate': [0, 1000000000],
        'audioRecordingSamplingRate': [4000, 96000],
      };
      for (final entry in kept.entries) {
        for (final value in entry.value) {
          test('${entry.key} $value is kept', () {
            expect(web({entry.key: value}), {entry.key: value});
          });
        }
      }
      for (final entry in dropped.entries) {
        for (final value in entry.value) {
          test('${entry.key} $value is dropped', () {
            expect(web({entry.key: value}), isEmpty);
          });
        }
      }

      test('validated keys are not also plain allowlist keys', () {
        expect(
          webAllowedSettings.intersection(webValidatedSettings.keys.toSet()),
          isEmpty,
        );
      });

      test('MDM stays unvalidated', () {
        expect(
          filterPlatformConfiguration({
            'fontSizeFactor': 1000.0,
          }, PlatformConfigSource.mdm),
          {'fontSizeFactor': 1000.0},
        );
      });
    });

    test('the removed spaces rail setting is no longer accepted', () {
      expect(web({'displayNavigationRail': true}), isEmpty);
    });

    test('unknown keys are dropped', () {
      expect(web({'somethingNew': 'x'}), isEmpty);
    });
  });

  group('filterPlatformConfiguration (MDM)', () {
    test('admin configuration keeps push and call settings', () {
      final config = <String, Object?>{
        'pushNotificationsGatewayUrl': 'https://push.corp.example/notify',
        'pushNotificationsPusherFormat': 'event_id_only',
        'fallbackLiveKitInstance': 'https://sfu.corp.example',
        'shareKeysWith': 'all',
        'applicationName': 'Corp',
      };
      expect(
        filterPlatformConfiguration(config, PlatformConfigSource.mdm),
        config,
      );
    });

    test('runtime state keys can never be configured', () {
      expect(
        filterPlatformConfiguration({
          'unifiedPushEndpoint': 'https://x',
          'unifiedPushRegistered': true,
          'noEncryptionWarningShown': true,
          'databaseUnencryptedClients': ['x'],
          'databaseUnencryptedNoticeDismissed': true,
          'knownErrorHashes': <String>[],
          'lastUpdateCheckDate': 'x',
          'showNoGoogle': true,
        }, PlatformConfigSource.mdm),
        isEmpty,
      );
    });
  });

  test('every AppSettings key is classified', () {
    final classified = {
      ...webAllowedSettings,
      ...webValidatedSettings.keys,
      ...webDeniedSettings,
    };
    expect(
      AppSettings.values.toSet().difference(classified),
      isEmpty,
      reason: 'add new settings to one of the web config lists',
    );
  });
}
