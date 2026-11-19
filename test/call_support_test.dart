// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:odango/utils/server_capabilities/call_support.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';
import 'package:odango/utils/server_capabilities/server_capabilities_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

class _Source implements ServerCapabilitySource {
  FeatureSupportAnswer answer;
  _Source(this.answer);

  @override
  Future<ServerCapabilityInputs> fetch() async => switch (answer) {
    FeatureSupportAnswer.supported => const ServerCapabilityInputs(
      versionsJson: {
        'versions': ['v1.1'],
      },
      wellKnownJson: {
        'org.matrix.msc4143.rtc_foci': [
          {'type': 'livekit', 'livekit_service_url': 'https://lk.example'},
        ],
      },
      hasAuthMetadata: false,
    ),
    FeatureSupportAnswer.unsupported => const ServerCapabilityInputs(
      versionsJson: {
        'versions': ['v1.1'],
      },
      wellKnownJson: <String, Object?>{},
      hasAuthMetadata: false,
    ),
    FeatureSupportAnswer.offline => throw const ServerCapabilitiesUnavailable(),
  };
}

enum FeatureSupportAnswer { supported, unsupported, offline }

const _homeserver = {
  'm.homeserver': {'base_url': 'https://fakeserver.notexisting'},
};

ServerCapabilities caps(FeatureSupport support) =>
    ServerCapabilities.unknown.withFeature(ServerFeature.groupCalls, support);

void main() {
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient(clientName: 'calls');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  group('callsAvailable', () {
    for (final support in FeatureSupport.values) {
      for (final enabled in [true, false]) {
        final expected =
            enabled &&
            (support == FeatureSupport.supported ||
                support == FeatureSupport.partial);
        test('${support.name}, setting ${enabled ? 'on' : 'off'}', () {
          expect(
            callsAvailable(enabled: enabled, capabilities: caps(support)),
            expected,
          );
        });
      }
    }
  });

  group('clientSupportsCalls', () {
    late RecordingApi api;
    late Client c;

    setUp(() async {
      api = RecordingApi();
      c = await prepareTestClient(clientName: 'sfu', httpClient: api);
    });

    test('a safe LiveKit url means supported', () async {
      api.getOverrides['/.well-known/matrix/client'] = {
        ..._homeserver,
        'org.matrix.msc4143.rtc_foci': [
          {'type': 'livekit', 'livekit_service_url': 'https://lk.example'},
        ],
      };
      expect(await clientSupportsCalls(c), isTrue);
    });

    test('no LiveKit url means unsupported', () async {
      api.getOverrides['/.well-known/matrix/client'] = _homeserver;
      expect(await clientSupportsCalls(c), isFalse);
    });

    test(
      'an unsafe url (credentials, plain http remote) does not count',
      () async {
        api.getOverrides['/.well-known/matrix/client'] = {
          ..._homeserver,
          'org.matrix.msc4143.rtc_foci': [
            {'type': 'livekit', 'livekit_service_url': 'http://remote.example'},
            {
              'type': 'livekit',
              'livekit_service_url': 'https://user:pw@lk.example',
            },
          ],
        };
        expect(await clientSupportsCalls(c), isFalse);
      },
    );

    test('a failing request means unsupported, never ringing', () async {
      api.onRequest = (_) async => throw const SocketException('offline');
      expect(await clientSupportsCalls(c), isFalse);
    });

    test('calls switched off means unsupported', () async {
      api.getOverrides['/.well-known/matrix/client'] = {
        ..._homeserver,
        'org.matrix.msc4143.rtc_foci': [
          {'type': 'livekit', 'livekit_service_url': 'https://lk.example'},
        ],
      };
      await AppSettings.callsEnabled.setItem(false);
      addTearDown(() => AppSettings.callsEnabled.setItem(true));
      expect(await clientSupportsCalls(c), isFalse);
    });
  });

  group('service notifications and persisted call support', () {
    late SharedPreferences prefs;
    late _Source source;
    late ServerCapabilitiesService service;
    var notified = 0;

    ServerCapabilitiesService build() {
      final built = ServerCapabilitiesService(
        store: prefs,
        sourceFor: (_) => source,
      )..addListener(() => notified++);
      addTearDown(built.dispose);
      return built;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      source = _Source(FeatureSupportAnswer.supported);
      notified = 0;
      service = build();
    });

    test('the first answer that shows calls notifies once', () async {
      await service.load(client, force: true);
      expect(notified, 1);
      await service.load(client, force: true);
      expect(notified, 1, reason: 'same answer, nothing to repaint');
    });

    test('an unsupported first answer does not notify', () async {
      source.answer = FeatureSupportAnswer.unsupported;
      await service.load(client, force: true);
      expect(notified, 0);
    });

    test('flipping off and on notifies each time', () async {
      await service.load(client, force: true);
      source.answer = FeatureSupportAnswer.unsupported;
      await service.load(client, force: true);
      expect(notified, 2);
      expect(
        callsAvailable(enabled: true, capabilities: service.cached(client)),
        isFalse,
      );
      source.answer = FeatureSupportAnswer.supported;
      await service.load(client, force: true);
      expect(notified, 3);
    });

    test(
      'forget never notifies: the account is gone, nothing to repaint',
      () async {
        await service.load(client, force: true);
        notified = 0;
        service.forget(client);
        expect(notified, 0);
        service.dispose();
        expect(() => service.forget(client), returnsNormally);
      },
    );

    test('the last answer is kept per account for the next start', () async {
      await service.load(client, force: true);
      final restarted = build();
      expect(
        callsAvailable(enabled: true, capabilities: restarted.cached(client)),
        isTrue,
        reason: 'shown before the first request finishes',
      );
    });

    test('a persisted false hides calls before the first request', () async {
      source.answer = FeatureSupportAnswer.unsupported;
      await service.load(client, force: true);
      final restarted = build();
      expect(
        callsAvailable(enabled: true, capabilities: restarted.cached(client)),
        isFalse,
      );
    });

    test('a live change after a restart updates and persists it', () async {
      await service.load(client, force: true);
      final restarted = build();
      source.answer = FeatureSupportAnswer.unsupported;
      notified = 0;
      await restarted.load(client, force: true);
      expect(notified, 1);
      final again = build();
      expect(
        callsAvailable(enabled: true, capabilities: again.cached(client)),
        isFalse,
      );
    });

    test('an offline start keeps the persisted answer', () async {
      await service.load(client, force: true);
      final restarted = build();
      source.answer = FeatureSupportAnswer.offline;
      await restarted.load(client, force: true);
      expect(
        callsAvailable(enabled: true, capabilities: restarted.cached(client)),
        isTrue,
      );
    });

    test('removing the account clears the persisted answer', () async {
      await service.load(client, force: true);
      service.forget(client);
      expect(
        prefs.getKeys().where(
          (key) =>
              key.startsWith(ServerCapabilitiesService.callSupportKeyPrefix),
        ),
        isEmpty,
      );
      expect(build().cached(client), ServerCapabilities.unknown);
    });

    test('only the support level is stored, no url', () async {
      await service.load(client, force: true);
      final stored = prefs
          .getKeys()
          .where(
            (key) =>
                key.startsWith(ServerCapabilitiesService.callSupportKeyPrefix),
          )
          .map(prefs.getString)
          .toList();
      expect(stored, ['supported']);
    });

    test('a garbage persisted value is ignored', () async {
      await prefs.setString(
        '${ServerCapabilitiesService.callSupportKeyPrefix}${client.clientName}',
        'https://lk.example/\u202e',
      );
      expect(build().cached(client), ServerCapabilities.unknown);
    });
  });

  group('planCallNotification', () {
    Event rtc({
      String? type = 'ring',
      String eventType = RtcNotificationContent.eventType,
    }) => Event(
      type: eventType,
      content: {
        'sender_ts': DateTime.now().millisecondsSinceEpoch,
        'notification_type': ?type,
      },
      room: Room(id: '!a:example.org', client: client),
      eventId: r'$e:example.org',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now(),
    );

    Event text() => Event(
      type: EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'hi'},
      room: Room(id: '!a:example.org', client: client),
      eventId: r'$m:example.org',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now(),
    );

    CallNotificationPlan plan(
      Event event, {
      required bool available,
      bool canRing = true,
    }) => planCallNotification(
      event,
      callsAvailable: available,
      canRing: canRing,
    );

    test('a ring on a server with calls rings', () {
      expect(plan(rtc(), available: true), CallNotificationPlan.ring);
    });

    test('a ring without calls is dropped entirely', () {
      expect(plan(rtc(), available: false), CallNotificationPlan.drop);
      expect(
        plan(rtc(), available: false, canRing: false),
        CallNotificationPlan.drop,
      );
    });

    test('a non-ring call notification without calls is dropped too', () {
      expect(
        plan(rtc(type: 'notification'), available: false),
        CallNotificationPlan.drop,
      );
    });

    test('a malformed call notification without calls is dropped', () {
      expect(
        plan(rtc(type: null), available: false),
        CallNotificationPlan.drop,
      );
    });

    test('with calls a ring that cannot ring here is a plain notification', () {
      expect(
        plan(rtc(), available: true, canRing: false),
        CallNotificationPlan.notify,
      );
      expect(
        plan(rtc(type: 'notification'), available: true),
        CallNotificationPlan.notify,
      );
    });

    test('messages are never touched by the call setting', () {
      expect(plan(text(), available: false), CallNotificationPlan.notify);
      expect(plan(text(), available: true), CallNotificationPlan.notify);
    });
  });

  test('both ring paths decide through planCallNotification (extra guard)', () {
    for (final (path, gate) in [
      ('lib/utils/push_helper.dart', 'await clientSupportsCalls(client)'),
      (
        'lib/widgets/local_notifications_extension.dart',
        'callsAvailableFor(event.room.client)',
      ),
    ]) {
      final source = File(path).readAsStringSync();
      final plan = source.indexOf('planCallNotification(');
      final gated = source.indexOf(gate, plan);
      final drop = source.indexOf('CallNotificationPlan.drop', plan);
      expect(plan, isNonNegative, reason: path);
      expect(gated, greaterThan(plan), reason: '$path asks $gate');
      expect(drop, greaterThan(gated), reason: '$path drops on the plan');
    }
  });
}
