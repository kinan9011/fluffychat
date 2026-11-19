// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/server_capabilities/call_support.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
          '/client/unstable/org.matrix.msc4143/rtc/transports',
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

class ServerCapabilitiesService extends ChangeNotifier {
  static const callSupportKeyPrefix = 'chat.fluffy.call_support.';

  final Duration maxAge;
  final Duration incompleteMaxAge;
  final Duration retryAfterFailure;
  final DateTime Function() _clock;
  final ServerCapabilitySource Function(Client) _sourceFor;
  final Map<Client, _Entry> _entries = Map.identity();
  final SharedPreferences? _store;
  bool _disposed = false;

  ServerCapabilitiesService({
    SharedPreferences? store,
    this.maxAge = const Duration(hours: 6),
    this.incompleteMaxAge = const Duration(minutes: 10),
    this.retryAfterFailure = const Duration(minutes: 1),
    DateTime Function()? clock,
    ServerCapabilitySource Function(Client)? sourceFor,
  }) : _store = store,
       _clock = clock ?? DateTime.now,
       _sourceFor = sourceFor ?? SdkServerCapabilitySource.new;

  /// The last known call support of an account, kept so the Calls tab does
  /// not pop in and out on every start. Only the support level is stored.
  ServerCapabilities? _persisted(Client client) {
    final raw = _store?.getString('$callSupportKeyPrefix${client.clientName}');
    final support = FeatureSupport.values.where((v) => v.name == raw);
    if (support.isEmpty || support.first == FeatureSupport.unknown) return null;
    return ServerCapabilities.unknown.withFeature(
      ServerFeature.groupCalls,
      support.first,
    );
  }

  void _persist(Client client, ServerCapabilities value) {
    final support = value[ServerFeature.groupCalls];
    if (support == FeatureSupport.unknown) return;
    unawaited(
      _store?.setString(
        '$callSupportKeyPrefix${client.clientName}',
        support.name,
      ),
    );
  }

  bool _callsShown(ServerCapabilities? value) =>
      value != null && callsAvailable(enabled: true, capabilities: value);

  ServerCapabilities cached(Client client) =>
      _entries[client]?.value ??
      _persisted(client) ??
      ServerCapabilities.unknown;

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
      final previous = entry.value ?? _persisted(client);
      final derived = ServerCapabilities.derive(inputs);
      final merged = previous == null
          ? derived
          : derived.fillUnknownFrom(previous);
      if (entry.generation != generation) return ServerCapabilities.unknown;
      entry.value = merged;
      _persist(client, merged);
      if (_callsShown(previous) != _callsShown(merged) && !_disposed) {
        notifyListeners();
      }
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
    unawaited(_store?.remove('$callSupportKeyPrefix${client.clientName}'));
    final entry = _entries.remove(client);
    if (entry == null) return;
    entry.generation++;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _entries.values) {
      entry.generation++;
    }
    _entries.clear();
    super.dispose();
  }
}
