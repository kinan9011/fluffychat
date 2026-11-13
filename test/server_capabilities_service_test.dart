// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'utils/test_client.dart';

class _FakeSource implements ServerCapabilitySource {
  final Future<ServerCapabilityInputs> Function() answer;
  int calls = 0;

  _FakeSource(this.answer);

  @override
  Future<ServerCapabilityInputs> fetch() {
    calls++;
    return answer();
  }
}

ServerCapabilityInputs _inputs({bool delayed = true, bool complete = true}) =>
    ServerCapabilityInputs(
      versionsJson: {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc4140': delayed},
      },
      wellKnownJson: complete ? const <String, Object?>{} : null,
      hasAuthMetadata: complete ? false : null,
    );

Future<Client> newClient(String name, {http.Client? httpClient}) async =>
    Client(
      name,
      httpClient: httpClient,
      database: await MatrixSdkDatabase.init(
        name,
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );

/// Answers every request like a broken or hostile homeserver would.
class _StubServer extends http.BaseClient {
  final http.StreamedResponse Function(http.BaseRequest request) respond;
  final List<Uri> requested = [];

  _StubServer(this.respond);

  factory _StubServer.status(int status, String body) => _StubServer(
    (request) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'application/json'},
    ),
  );

  factory _StubServer.offline() =>
      _StubServer((_) => throw const SocketException('offline'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    return respond(request);
  }
}

Future<Client> _clientOn(_StubServer server) async {
  final client = await newClient('stub', httpClient: server);
  client.homeserver = Uri.parse('https://server.example');
  return client;
}

void main() {
  late DateTime now;
  late Map<Client, _FakeSource> sources;
  late ServerCapabilitiesService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    now = DateTime(2030);
    sources = {};
    service = ServerCapabilitiesService(
      clock: () => now,
      sourceFor: (client) => sources[client]!,
    );
  });

  tearDown(() => service.dispose());

  group('cache', () {
    test('nothing cached means unknown', () async {
      final client = await newClient('a');
      expect(service.cached(client), ServerCapabilities.unknown);
    });

    test('load caches and reuses the result while fresh', () async {
      final client = await newClient('a');
      final source = sources[client] = _FakeSource(() async => _inputs());
      final first = await service.load(client);
      expect(first.supports(ServerFeature.delayedEvents), isTrue);
      expect(service.cached(client), same(first));
      now = now.add(const Duration(hours: 5, minutes: 59));
      expect(await service.load(client), same(first));
      expect(source.calls, 1);
    });

    test('refreshes after maxAge and on force', () async {
      final client = await newClient('a');
      final source = sources[client] = _FakeSource(() async => _inputs());
      await service.load(client);
      now = now.add(const Duration(hours: 6, seconds: 1));
      await service.load(client);
      expect(source.calls, 2);
      await service.load(client, force: true);
      expect(source.calls, 3);
    });

    test('an incomplete answer is only trusted for ten minutes', () async {
      final client = await newClient('a');
      final source = sources[client] = _FakeSource(
        () async => _inputs(complete: false),
      );
      await service.load(client);
      now = now.add(const Duration(minutes: 9));
      await service.load(client);
      expect(source.calls, 1);
      now = now.add(const Duration(minutes: 2));
      await service.load(client);
      expect(source.calls, 2);
    });

    test('a later partial answer keeps what was known before', () async {
      final client = await newClient('a');
      var complete = true;
      sources[client] = _FakeSource(() async => _inputs(complete: complete));
      await service.load(client);
      complete = false;
      final merged = await service.load(client, force: true);
      expect(merged.supports(ServerFeature.delayedEvents), isTrue);
    });

    test('concurrent loads share one request', () async {
      final client = await newClient('a');
      final completer = Completer<ServerCapabilityInputs>();
      final source = sources[client] = _FakeSource(() => completer.future);
      final a = service.load(client);
      final b = service.load(client);
      completer.complete(_inputs());
      expect(await a, same(await b));
      expect(source.calls, 1);
    });
  });

  group('failures', () {
    test(
      'a failure gives unknown, is not cached for hours, retries soon',
      () async {
        final client = await newClient('a');
        var fail = true;
        final source = sources[client] = _FakeSource(() async {
          if (fail) throw const ServerCapabilitiesUnavailable();
          return _inputs();
        });
        expect(await service.load(client), ServerCapabilities.unknown);
        now = now.add(const Duration(seconds: 59));
        await service.load(client);
        expect(source.calls, 1, reason: 'inside the retry window');
        fail = false;
        now = now.add(const Duration(seconds: 2));
        final ok = await service.load(client);
        expect(source.calls, 2);
        expect(ok.supports(ServerFeature.delayedEvents), isTrue);
      },
    );

    test(
      'a failed refresh keeps the last good value, also when forced',
      () async {
        final client = await newClient('a');
        var fail = false;
        sources[client] = _FakeSource(() async {
          if (fail) throw const ServerCapabilitiesUnavailable();
          return _inputs();
        });
        final good = await service.load(client);
        fail = true;
        expect(await service.load(client, force: true), same(good));
        expect(service.cached(client), same(good));
        now = now.add(const Duration(hours: 7));
        expect(await service.load(client), same(good));
      },
    );

    test('two accounts never share capabilities', () async {
      final a = await newClient('a');
      final b = await newClient('b');
      sources[a] = _FakeSource(() async => _inputs());
      sources[b] = _FakeSource(() async => _inputs(delayed: false));
      await Future.wait([service.load(a), service.load(b)]);
      expect(service.cached(a).supports(ServerFeature.delayedEvents), isTrue);
      expect(
        service.cached(b)[ServerFeature.delayedEvents],
        FeatureSupport.unsupported,
      );
      service.forget(a);
      expect(service.cached(a), ServerCapabilities.unknown);
      expect(
        service.cached(b)[ServerFeature.delayedEvents],
        FeatureSupport.unsupported,
      );
    });

    test('a result that arrives after forget is dropped', () async {
      final client = await newClient('a');
      final completer = Completer<ServerCapabilityInputs>();
      sources[client] = _FakeSource(() => completer.future);
      final pending = service.load(client);
      service.forget(client);
      completer.complete(_inputs());
      await pending;
      expect(service.cached(client), ServerCapabilities.unknown);
    });
  });

  group('SdkServerCapabilitySource against real failing servers', () {
    test(
      'offline: nothing answers, fetch reports it instead of unknown',
      () async {
        final server = _StubServer.offline();
        final client = await _clientOn(server);
        await expectLater(
          SdkServerCapabilitySource(client).fetch(),
          throwsA(isA<ServerCapabilitiesUnavailable>()),
        );
        expect(server.requested, isNotEmpty);
      },
    );

    test('5xx pages and garbage bodies never become answers', () async {
      for (final response in [
        (500, '<html>oops</html>'),
        (502, ''),
        (200, '[1,2,3]'),
        (200, '"just a string"'),
        (200, '{"versions": 5}'),
        (200, '{"unstable_features": {"org.matrix.msc4140": "yes"}}'),
        (200, '${'{"a":' * 5000}1${'}' * 5000}'),
      ]) {
        final client = await _clientOn(
          _StubServer.status(response.$1, response.$2),
        );
        try {
          final inputs = await SdkServerCapabilitySource(client).fetch();
          final caps = ServerCapabilities.derive(inputs);
          for (final feature in ServerFeature.values) {
            if (feature == ServerFeature.serverSideSearchE2ee) continue;
            expect(
              caps[feature],
              isNot(FeatureSupport.supported),
              reason: '$response $feature',
            );
          }
        } on ServerCapabilitiesUnavailable {
          // fine: everything failed
        }
      }
    });

    test(
      'the service stays on unknown, retries after the window and recovers',
      () async {
        var online = false;
        final server = _StubServer(
          (request) => online
              ? http.StreamedResponse(
                  Stream.value(
                    utf8.encode(
                      request.url.path.endsWith('/versions')
                          ? jsonEncode({
                              'versions': ['v1.1'],
                              'unstable_features': {'org.matrix.msc4140': true},
                            })
                          : '{}',
                    ),
                  ),
                  200,
                  headers: {'content-type': 'application/json'},
                )
              : throw const SocketException('offline'),
        );
        final client = await _clientOn(server);
        final real = ServerCapabilitiesService(clock: () => now);
        addTearDown(real.dispose);
        expect(await real.load(client), ServerCapabilities.unknown);
        final requests = server.requested.length;
        now = now.add(const Duration(seconds: 30));
        await real.load(client);
        expect(server.requested.length, requests, reason: 'backoff');
        online = true;
        now = now.add(const Duration(minutes: 2));
        final recovered = await real.load(client);
        expect(recovered.supports(ServerFeature.delayedEvents), isTrue);
      },
    );

    test(
      'uses only the account homeserver and the five known endpoints',
      () async {
        final client = await prepareTestClient(loggedIn: true);
        FakeMatrixApi.calledEndpoints.clear();
        final inputs = await SdkServerCapabilitySource(client).fetch();
        final called = FakeMatrixApi.calledEndpoints.keys
            .where((path) => !path.contains('/sync'))
            .toSet();
        expect(inputs.versionsJson, isA<Map>());
        expect(
          called.every(
            (path) =>
                path.contains('/client/versions') ||
                path.contains('/.well-known/matrix/client') ||
                path.contains('/org.matrix.msc4143/rtc/transports') ||
                path.contains('/client/v3/capabilities') ||
                path.contains('/client/v1/auth_metadata'),
          ),
          isTrue,
          reason: '$called',
        );
        final caps = ServerCapabilities.derive(inputs);
        expect(caps.features.length, ServerFeature.values.length);
      },
    );

    test('a failing service logs only the exception type', () async {
      final log = StringBuffer();
      Logs().level = Level.verbose;
      final before = Logs().outputEvents.length;
      final client = await newClient('log');
      final throwing = ServerCapabilitiesService(
        sourceFor: (_) =>
            _FakeSource(() => throw StateError('canary-secret-body')),
      );
      expect(await throwing.load(client), ServerCapabilities.unknown);
      for (final event in Logs().outputEvents.skip(before)) {
        log.writeln('${event.title} ${event.exception}');
      }
      expect(log.toString(), isNot(contains('canary-secret-body')));
      throwing.dispose();
    });
  });
}
