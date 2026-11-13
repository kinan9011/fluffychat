// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:matrix/matrix.dart';

class ServerCapabilitiesUnavailable implements Exception {
  const ServerCapabilitiesUnavailable();
}

abstract class ServerCapabilitySource {
  Future<ServerCapabilityInputs> fetch();
}

class SdkServerCapabilitySource implements ServerCapabilitySource {
  static const timeout = Duration(seconds: 10);

  final Client client;

  const SdkServerCapabilitySource(this.client);

  Future<T?> _guard<T>(String name, Future<T> Function() request) async {
    try {
      return await request().timeout(timeout);
    } catch (e) {
      Logs().d('[ServerCapabilities] $name unavailable (${e.runtimeType})');
      return null;
    }
  }

  // The SDK buffers whole bodies, so size limits can only apply to the
  // parsed values (see ServerCapabilities.maxNodes), not to the transport.
  @override
  Future<ServerCapabilityInputs> fetch() async {
    final results = await Future.wait<Object?>([
      _guard(
        'versions',
        () async =>
            (await client.getVersions(cacheLifetime: Duration.zero)).toJson(),
      ),
      _guard('well-known', () async => (await client.getWellknown()).toJson()),
      _guard(
        'rtc transports',
        () => client.request(
          .GET,
          '/_matrix/client/unstable/org.matrix.msc4143/rtc/transports',
        ),
      ),
      _guard(
        'capabilities',
        () async => (await client.getCapabilities()).toJson(),
      ),
      _guard('auth metadata', () async {
        try {
          await client.getAuthMetadata();
          return true;
        } on MatrixException catch (e) {
          if (e.response?.statusCode == 404 || e.errcode == 'M_UNRECOGNIZED') {
            return false;
          }
          rethrow;
        }
      }),
    ]);
    if (results.every((result) => result == null)) {
      throw const ServerCapabilitiesUnavailable();
    }
    final [versions, wellKnown, transports, capabilities, authMetadata] =
        results;
    return ServerCapabilityInputs(
      versionsJson: versions,
      wellKnownJson: wellKnown,
      rtcTransportsJson: transports,
      capabilitiesJson: capabilities,
      hasAuthMetadata: authMetadata as bool?,
      fallbackLiveKitConfigured:
          AppSettings.fallbackLiveKitInstance.value.isNotEmpty,
    );
  }
}

class _Entry {
  ServerCapabilities? value;
  DateTime? fetchedAt;
  DateTime? retryAt;
  Duration ttl = Duration.zero;
  Future<ServerCapabilities>? inFlight;
  int generation = 0;
}

class ServerCapabilitiesService {
  final Duration maxAge;
  final Duration incompleteMaxAge;
  final Duration retryAfterFailure;
  final DateTime Function() _clock;
  final ServerCapabilitySource Function(Client) _sourceFor;
  final Map<Client, _Entry> _entries = Map.identity();

  ServerCapabilitiesService({
    this.maxAge = const Duration(hours: 6),
    this.incompleteMaxAge = const Duration(minutes: 10),
    this.retryAfterFailure = const Duration(minutes: 1),
    DateTime Function()? clock,
    ServerCapabilitySource Function(Client)? sourceFor,
  }) : _clock = clock ?? DateTime.now,
       _sourceFor = sourceFor ?? SdkServerCapabilitySource.new;

  ServerCapabilities cached(Client client) =>
      _entries[client]?.value ?? ServerCapabilities.unknown;

  Future<ServerCapabilities> load(Client client, {bool force = false}) {
    final entry = _entries.putIfAbsent(client, _Entry.new);
    final value = entry.value;
    final now = _clock();
    if (!force) {
      final retryAt = entry.retryAt;
      if (retryAt != null && now.isBefore(retryAt)) {
        return Future.value(value ?? ServerCapabilities.unknown);
      }
      final fetchedAt = entry.fetchedAt;
      if (value != null &&
          fetchedAt != null &&
          now.difference(fetchedAt) < entry.ttl) {
        return Future.value(value);
      }
    }
    return entry.inFlight ??= _refresh(client, entry);
  }

  Future<ServerCapabilities> _refresh(Client client, _Entry entry) async {
    final generation = entry.generation;
    try {
      final inputs = await _sourceFor(client).fetch();
      final previous = entry.value;
      final derived = ServerCapabilities.derive(inputs);
      final merged = previous == null
          ? derived
          : derived.fillUnknownFrom(previous);
      if (entry.generation != generation) return ServerCapabilities.unknown;
      entry.value = merged;
      entry.fetchedAt = _clock();
      entry.retryAt = null;
      entry.ttl = inputs.isComplete ? maxAge : incompleteMaxAge;
      return merged;
    } catch (e) {
      Logs().d('[ServerCapabilities] refresh failed (${e.runtimeType})');
      if (entry.generation != generation) return ServerCapabilities.unknown;
      entry.retryAt = _clock().add(retryAfterFailure);
      return entry.value ?? ServerCapabilities.unknown;
    } finally {
      if (entry.generation == generation) entry.inFlight = null;
    }
  }

  void forget(Client client) {
    final entry = _entries.remove(client);
    if (entry == null) return;
    entry.generation++;
  }

  void dispose() {
    for (final entry in _entries.values) {
      entry.generation++;
    }
    _entries.clear();
  }
}
