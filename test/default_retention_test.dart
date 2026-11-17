// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/retention/default_retention.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

ServerCapabilities _caps({required bool retention}) =>
    ServerCapabilities.derive(
      ServerCapabilityInputs(
        versionsJson: {
          'versions': ['v1.1'],
          'unstable_features': {'org.matrix.msc1763': retention},
        },
        wellKnownJson: const {},
        hasAuthMetadata: false,
      ),
    );

class _Source implements ServerCapabilitySource {
  _Source(this.caps);
  final ServerCapabilities caps;
  int fetches = 0;

  @override
  Future<ServerCapabilityInputs> fetch() async {
    fetches++;
    return ServerCapabilityInputs(
      versionsJson: {
        'versions': ['v1.1'],
        'unstable_features': {
          'org.matrix.msc1763': caps.supports(ServerFeature.retention),
        },
      },
      wellKnownJson: const {},
      hasAuthMetadata: false,
    );
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
  });

  group('normalize', () {
    test('only off and the three presets are allowed', () {
      expect(DefaultRetention.allowedSeconds, [0, 86400, 604800, 2592000]);
      for (final ok in DefaultRetention.allowedSeconds) {
        expect(DefaultRetention.normalize(ok), ok);
      }
    });

    for (final bad in [-1, 1, 3600, 86401, 1 << 40, 99999999999]) {
      test(
        '$bad becomes off',
        () => expect(DefaultRetention.normalize(bad), 0),
      );
    }
  });

  group('initialState', () {
    test('off (the default) adds nothing', () {
      expect(
        DefaultRetention.initialState(caps: _caps(retention: true)),
        isEmpty,
      );
    });

    test('a timer on a server with retention adds one state event', () {
      final events = DefaultRetention.initialState(
        caps: _caps(retention: true),
        seconds: 604800,
      );
      expect(events, hasLength(1));
      expect(events.single.type, 'm.room.retention');
      expect(events.single.stateKey ?? '', '');
      expect(events.single.content, {
        'max_lifetime': 604800000,
        'expire_on_clients': true,
      });
    });

    test('a server without retention, or an unknown one, adds nothing', () {
      expect(
        DefaultRetention.initialState(
          caps: _caps(retention: false),
          seconds: 604800,
        ),
        isEmpty,
      );
      expect(
        DefaultRetention.initialState(
          caps: ServerCapabilities.unknown,
          seconds: 604800,
        ),
        isEmpty,
      );
    });

    test('a value that is not allowed adds nothing', () {
      expect(
        DefaultRetention.initialState(caps: _caps(retention: true), seconds: 5),
        isEmpty,
      );
    });

    test('the stored setting is used and normalised', () async {
      await AppSettings.defaultDisappearSeconds.setItem(86400);
      expect(
        DefaultRetention.initialState(caps: _caps(retention: true)),
        hasLength(1),
      );
      await AppSettings.defaultDisappearSeconds.setItem(77);
      expect(
        DefaultRetention.initialState(caps: _caps(retention: true)),
        isEmpty,
      );
    });
  });

  group('initialStateFor', () {
    late Client client;
    setUp(() async => client = await prepareTestClient());
    tearDown(() => client.dispose(closeDatabase: true));

    test('does not ask the server while the timer is off', () async {
      final source = _Source(_caps(retention: true));
      final service = ServerCapabilitiesService(sourceFor: (_) => source);
      expect(await DefaultRetention.initialStateFor(service, client), isEmpty);
      expect(source.fetches, 0);
    });

    test('asks the server once the timer is on', () async {
      await AppSettings.defaultDisappearSeconds.setItem(2592000);
      final source = _Source(_caps(retention: true));
      final service = ServerCapabilitiesService(sourceFor: (_) => source);
      expect(
        await DefaultRetention.initialStateFor(service, client),
        hasLength(1),
      );
      expect(source.fetches, 1);
    });
  });

  group('web config.json cannot turn the timer on', () {
    test('the key is denied for web and accepted from MDM', () {
      expect(
        filterPlatformConfiguration({
          'defaultDisappearSeconds': 86400,
        }, PlatformConfigSource.web),
        isEmpty,
      );
      expect(
        filterPlatformConfiguration({
          'defaultDisappearSeconds': 86400,
        }, PlatformConfigSource.mdm),
        {'defaultDisappearSeconds': 86400},
      );
    });

    test('Away cannot be set from a web config.json either', () {
      expect(
        filterPlatformConfiguration({
          'presenceAway': true,
        }, PlatformConfigSource.web),
        isEmpty,
      );
    });
  });

  group('every room creation goes through the helper', () {
    test('the sites that start chats ask for the default timer', () {
      for (final path in [
        'lib/widgets/adaptive_dialogs/user_dialog.dart',
        'lib/pages/new_group/new_group.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains('DefaultRetention.initialStateFor('),
          reason: path,
        );
      }
    });

    test('no other file creates a chat without it', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.startsWith('lib/l10n/')) continue;
        final text = entity.readAsStringSync();
        final creates =
            text.contains('.startDirectChat(') ||
            text.contains('.createGroupChat(');
        if (creates && !text.contains('DefaultRetention.')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
