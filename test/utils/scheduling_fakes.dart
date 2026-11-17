// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/scheduling/delayed_events_api.dart';
import 'package:fluffychat/utils/scheduling/scheduled_messages.dart';
import 'package:fluffychat/utils/scheduling/scheduled_queue.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:matrix/matrix.dart';

/// Keeps the one custom document in memory: no sqlite, no real timers.
class MemoryDatabase implements DatabaseApi {
  Map<String, Object?>? document;
  bool failingWrites = false;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {
    if (failingWrites) throw StateError('SENTINEL-DB-FAILURE');
    document = Map.of(object);
  }

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async =>
      document == null ? null : (content: document!, savedAt: DateTime(2025));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeCapabilitySource implements ServerCapabilitySource {
  FakeCapabilitySource({this.supported = true});

  final bool supported;

  @override
  Future<ServerCapabilityInputs> fetch() async => ServerCapabilityInputs(
    versionsJson: {
      'versions': ['v1.11'],
      'unstable_features': {'org.matrix.msc4140': supported},
    },
    wellKnownJson: const <String, Object?>{},
    hasAuthMetadata: false,
  );
}

class FakeDelayedApi implements DelayedEventsApi {
  FakeDelayedApi(this.client);

  @override
  final Client client;
  final log = <String>[];
  final listed = <ServerDelayedEvent>[];
  Object? listError;
  Object? scheduleError;
  Object? cancelError;
  var counter = 0;

  @override
  Future<String> scheduleMessage(
    Room room,
    Map<String, Object?> content,
    Duration delay,
  ) async {
    log.add('schedule');
    if (scheduleError != null) throw scheduleError!;
    return 'delay-${++counter}';
  }

  @override
  Future<({List<ServerDelayedEvent> events, bool complete})> list() async {
    log.add('list');
    if (listError != null) throw listError!;
    return (events: List.of(listed), complete: true);
  }

  @override
  Future<void> sendNow(String delayId) async => log.add('send $delayId');

  @override
  Future<void> cancel(String delayId) async {
    log.add('cancel $delayId');
    if (cancelError != null) throw cancelError!;
  }
}

/// One account with an in-memory store, a fake server and a queue that only
/// records what it was asked to send.
class SchedulingFixture {
  SchedulingFixture(this.client, this.room, {bool serverSupported = false}) {
    store = ScheduledStore.forTesting(() => database, now: () => now);
    api = FakeDelayedApi(client);
    queue = ScheduledQueue(
      store,
      send: (roomId, content) async => sent.add(content),
      now: () => now,
    );
    messages = ScheduledMessages(
      client,
      capabilities: ServerCapabilitiesService(
        sourceFor: (_) => FakeCapabilitySource(supported: serverSupported),
      ),
      api: api,
      store: store,
      queue: queue,
      now: () => now,
      modeTimeout: const Duration(milliseconds: 50),
    );
  }

  final Client client;
  final Room room;
  final database = MemoryDatabase();
  late final ScheduledStore store;
  late final FakeDelayedApi api;
  late final ScheduledQueue queue;
  late final ScheduledMessages messages;
  final sent = <Map<String, Object?>>[];
  DateTime now = DateTime(2025, 11, 13, 14, 30);

  ScheduledEntry entry(
    String id,
    String body, {
    DateTime? at,
    String? untilOnline,
    ScheduledMode mode = ScheduledMode.device,
    ScheduledState state = ScheduledState.pending,
    ScheduledFailure? reason,
    bool encrypted = false,
  }) => ScheduledEntry(
    id: id,
    roomId: room.id,
    mode: mode,
    sendAt: untilOnline == null ? at : null,
    untilOnline: untilOnline,
    createdAt: now,
    delayId: mode == ScheduledMode.server ? 'delay-$id' : null,
    state: state,
    reason: reason,
    encrypted: encrypted,
    content: {'msgtype': 'm.text', 'body': body},
  );

  void dispose() => queue.stop();
}
