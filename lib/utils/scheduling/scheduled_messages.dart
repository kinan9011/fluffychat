// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:odango/utils/scheduling/delayed_events_api.dart';
import 'package:odango/utils/scheduling/schedule_time.dart';
import 'package:odango/utils/scheduling/scheduled_content.dart';
import 'package:odango/utils/scheduling/scheduled_queue.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';
import 'package:odango/utils/server_capabilities/server_capabilities_service.dart';

enum ScheduleError {
  tooSoon,
  tooFar,
  unsupported,
  tooMany,
  encryptionUnavailable,
  storageUnavailable,
  alreadySent,
  failed,
}

class ScheduleException implements Exception {
  const ScheduleException(this.error, {this.maxDays});

  final ScheduleError error;
  final int? maxDays;

  @override
  String toString() => 'ScheduleException(${error.name})';
}

/// A scheduled message as the list shows it: ours (with its text) or one that
/// only the server knows about (scheduled on another device).
class ScheduledItem {
  const ScheduledItem({this.local, this.server, this.sendsUnencrypted = false})
    : assert(local != null || server != null);

  final ScheduledEntry? local;
  final ServerDelayedEvent? server;

  /// The server holds it as plain text and the room has been encrypted since.
  final bool sendsUnencrypted;

  String get key => local?.id ?? 'server:${server!.delayId}';
  String get roomId => local?.roomId ?? server!.roomId;
  DateTime? get sendAt => local?.sendAt ?? server?.sendAt;
  String? get untilOnline => local?.untilOnline;
  bool get fromOtherDevice => local == null;
  bool get failed => local?.state == ScheduledState.failed;

  /// The server holds this one (and sends it at its time).
  bool get onServer =>
      server != null ||
      local != null &&
          local!.mode == ScheduledMode.server &&
          local!.state != ScheduledState.failed;

  /// The text shown as plain text only: the server copy of a message from
  /// another device is only readable when the room is not encrypted.
  String get preview => ScheduledContent.previewOf(
    local?.content ??
        (server!.type == EventTypes.Message ? server!.content : {}),
  );

  /// Needs the text, so only entries this device wrote.
  bool get canReschedule => local != null && local!.untilOnline == null;
}

class ScheduledList {
  const ScheduledList(this.items, {this.serverListFailed = false});

  final List<ScheduledItem> items;
  final bool serverListFailed;
}

/// What the UI uses: chooses the mode, keeps the local record of every
/// message next to what the server holds, and turns every failure into a
/// [ScheduleException] the UI can phrase.
class ScheduledMessages {
  ScheduledMessages(
    this.client, {
    required ServerCapabilitiesService capabilities,
    DelayedEventsApi? api,
    ScheduledStore? store,
    ScheduledQueue? queue,
    DateTime Function()? now,
    this.modeTimeout = const Duration(seconds: 3),
  }) : _capabilities = capabilities,
       _api = api ?? DelayedEventsApi(client),
       _givenStore = store,
       _givenQueue = queue,
       _now = now ?? DateTime.now;

  static final _instances = Expando<ScheduledMessages>('ScheduledMessages');

  /// One per account, so the counts the chat shows and the list agree.
  static ScheduledMessages of(
    Client client,
    ServerCapabilitiesService capabilities,
  ) => _instances[client] ??= ScheduledMessages(
    client,
    capabilities: capabilities,
  );

  final Client client;
  final Duration modeTimeout;
  final ServerCapabilitiesService _capabilities;
  final DelayedEventsApi _api;
  final ScheduledStore? _givenStore;
  final ScheduledQueue? _givenQueue;
  final DateTime Function() _now;
  final _serverOnly = <String, int>{};

  /// Looked up each time: a logout drops the account's store and queue.
  ScheduledStore get _store => _givenStore ?? ScheduledStore.of(client);
  ScheduledQueue get _queue => _givenQueue ?? ScheduledQueue.of(client);

  Future<bool> _serverSchedules() async {
    final capabilities = await _capabilities
        .load(client)
        .timeout(modeTimeout, onTimeout: () => _capabilities.cached(client));
    return capabilities.supports(ServerFeature.delayedEvents);
  }

  Future<ScheduledMode> modeFor() async =>
      await _serverSchedules() ? ScheduledMode.server : ScheduledMode.device;

  int countFor(String roomId) =>
      _store.entries(roomId: roomId).length + (_serverOnly[roomId] ?? 0);

  bool hasFailed(String roomId) => _store
      .entries(roomId: roomId)
      .any((e) => e.state == ScheduledState.failed);

  ScheduleException _map(Object error) {
    if (error is ScheduleException) return error;
    if (error is ScheduleDelayTooShort) {
      return const ScheduleException(ScheduleError.tooSoon);
    }
    if (error is ScheduledCapReached) {
      return const ScheduleException(ScheduleError.tooMany);
    }
    if (error is ScheduledStorageUnavailable) {
      return const ScheduleException(ScheduleError.storageUnavailable);
    }
    if (error is ScheduledEncryptionUnavailable) {
      return const ScheduleException(ScheduleError.encryptionUnavailable);
    }
    if (error is MatrixException) {
      if (error.errcode == 'M_MAX_DELAY_EXCEEDED') {
        final max = error.raw['max_delay'];
        return ScheduleException(
          ScheduleError.tooFar,
          maxDays: max is int ? max ~/ Duration.millisecondsPerDay : null,
        );
      }
      final status = error.response?.statusCode;
      if (status == 404 || status == 405 || error.errcode == 'M_UNRECOGNIZED') {
        unawaited(_capabilities.load(client, force: true));
        return const ScheduleException(ScheduleError.unsupported);
      }
    }
    return const ScheduleException(ScheduleError.failed);
  }

  void _checkTime(DateTime at) {
    switch (ScheduleRules.validate(at, _now())) {
      case ScheduleValidity.ok:
        return;
      case ScheduleValidity.tooSoon:
        throw const ScheduleException(ScheduleError.tooSoon);
      case ScheduleValidity.tooFar:
        throw const ScheduleException(ScheduleError.tooFar);
    }
  }

  /// Stores the message and has the chosen side send it at [at]. On a server
  /// failure nothing is stored; the text stays in the composer.
  Future<void> schedule(
    Room room,
    Map<String, Object?> content,
    DateTime at,
    ScheduledMode mode,
  ) async {
    _checkTime(at);
    try {
      final now = _now();
      if (mode == ScheduledMode.device) {
        await _store.put(
          ScheduledEntry(
            id: ScheduledEntry.newId(),
            roomId: room.id,
            mode: mode,
            sendAt: at,
            createdAt: now,
            content: content,
          ),
        );
        unawaited(_queue.evaluate());
        return;
      }
      await _scheduleOnServer(room, content, at, now);
    } catch (e) {
      throw _map(e);
    }
  }

  /// With [replacing] (a reschedule) the new record takes the place of that
  /// entry, which is always allowed; otherwise the store must have room.
  Future<void> _scheduleOnServer(
    Room room,
    Map<String, Object?> content,
    DateTime at,
    DateTime now, {
    ScheduledEntry? replacing,
  }) async {
    await _store.ready;
    if (replacing == null &&
        _store.entries().length >= ScheduledStore.maxEntries) {
      throw const ScheduledCapReached();
    }
    final delayId = await _api.scheduleMessage(
      room,
      content,
      at.difference(now),
    );
    final entry = ScheduledEntry(
      id: replacing?.id ?? ScheduledEntry.newId(),
      roomId: room.id,
      mode: ScheduledMode.server,
      sendAt: at,
      createdAt: now,
      delayId: delayId,
      encrypted: room.encrypted,
      content: content,
    );
    try {
      if (replacing == null) {
        await _store.put(entry);
        return;
      }
      final stored = await _store.update(
        entry.id,
        (c) =>
            c.mode == ScheduledMode.device && c.state != ScheduledState.sending
            ? entry
            : null,
      );
      if (stored == null) throw const ScheduleException(ScheduleError.failed);
    } catch (_) {
      try {
        await _api.cancel(delayId);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> scheduleWhenOnline(
    Room room,
    Map<String, Object?> content,
    String userId,
  ) async {
    try {
      await _store.put(
        ScheduledEntry(
          id: ScheduledEntry.newId(),
          roomId: room.id,
          mode: ScheduledMode.device,
          untilOnline: userId,
          createdAt: _now(),
          content: content,
        ),
      );
      unawaited(_queue.evaluate());
    } catch (e) {
      throw _map(e);
    }
  }

  /// Brings the counts of [room] up to date without asking the capability
  /// service or the server when this account has never scheduled anything on
  /// it: opening a chat must stay cheap.
  Future<void> refreshCounts(Room room) async {
    await _store.ready;
    final known =
        _store.entries().any((e) => e.mode == ScheduledMode.server) ||
        _capabilities.cached(client).supports(ServerFeature.delayedEvents);
    if (known) await load(room);
  }

  Future<ScheduledList> load(Room room) async {
    await _store.ready;
    final local = _store.entries();
    final hasServerRecord = local.any((e) => e.mode == ScheduledMode.server);
    final serverKnown = hasServerRecord || await _serverSchedules();
    var listFailed = false;
    var serverOnly = <ServerDelayedEvent>[];
    if (serverKnown) {
      try {
        final listed = await _api.list();
        final ids = {for (final e in listed.events) e.delayId};
        if (listed.complete) {
          for (final entry in local) {
            if (entry.mode == ScheduledMode.server &&
                entry.state != ScheduledState.failed &&
                !ids.contains(entry.delayId)) {
              await _store.remove(entry.id);
            }
          }
        }
        final known = {
          for (final e in _store.entries())
            if (e.delayId != null) e.delayId,
        };
        serverOnly = [
          for (final e in listed.events)
            if (e.roomId == room.id && !known.contains(e.delayId)) e,
        ];
      } catch (_) {
        listFailed = true;
      }
    }
    _serverOnly[room.id] = serverOnly.length;
    return ScheduledList([
      for (final e in _store.entries(roomId: room.id))
        ScheduledItem(local: e, sendsUnencrypted: _sendsUnencrypted(e)),
      for (final e in serverOnly) ScheduledItem(server: e),
    ], serverListFailed: listFailed);
  }

  bool _sendsUnencrypted(ScheduledEntry e) =>
      e.mode == ScheduledMode.server &&
      e.state != ScheduledState.failed &&
      !e.encrypted &&
      client.getRoomById(e.roomId)?.encrypted == true;

  bool _gone(Object error) =>
      error is MatrixException && error.errcode == 'M_NOT_FOUND';

  Future<void> sendNow(ScheduledItem item) async {
    try {
      if (!item.onServer) {
        await _queue.sendNow(item.local!.id);
        return;
      }
      await _api.sendNow(item.local?.delayId ?? item.server!.delayId);
      if (item.local != null) await _store.remove(item.local!.id);
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> delete(ScheduledItem item) async {
    try {
      if (item.onServer) {
        try {
          await _api.cancel(item.local?.delayId ?? item.server!.delayId);
        } catch (e) {
          if (!_gone(e)) rethrow;
        }
      }
      if (item.local != null) await _store.remove(item.local!.id);
    } catch (e) {
      throw _map(e);
    }
  }

  /// A new time for a message of this device. The old server copy is
  /// cancelled first and the text is kept as a local record until the new
  /// schedule is stored, so a failure never loses the message and never
  /// sends it twice. The entry is looked up again by id for every change: one
  /// the queue or the server sent while the picker was open ([ScheduleError.alreadySent])
  /// is not brought back and scheduled a second time.
  Future<void> reschedule(ScheduledItem item, DateTime at) async {
    final local = item.local;
    if (local == null || !item.canReschedule) {
      throw const ScheduleException(ScheduleError.failed);
    }
    _checkTime(at);
    try {
      var current = local;
      if (item.onServer) {
        final held = await _store.update(
          local.id,
          (c) =>
              c.mode == ScheduledMode.server &&
                  c.state == ScheduledState.pending &&
                  c.delayId == local.delayId
              ? c.asFailedDevice()
              : null,
        );
        if (held == null) {
          throw const ScheduleException(ScheduleError.alreadySent);
        }
        try {
          await _api.cancel(local.delayId!);
        } catch (e) {
          if (_gone(e)) {
            await _store.remove(local.id);
            throw const ScheduleException(ScheduleError.alreadySent);
          }
          await _restore(local);
          rethrow;
        }
        current = held;
      }
      final room = client.getRoomById(local.roomId);
      if (room == null) throw const ScheduleException(ScheduleError.failed);
      final mode = await modeFor();
      if (mode == ScheduledMode.device) {
        final moved = await _store.update(
          local.id,
          (c) => c.state == ScheduledState.sending
              ? null
              : c.copyWith(sendAt: at, state: ScheduledState.pending),
        );
        if (moved == null) {
          throw const ScheduleException(ScheduleError.alreadySent);
        }
        unawaited(_queue.evaluate());
        return;
      }
      await _scheduleOnServer(
        room,
        local.content,
        at,
        _now(),
        replacing: current,
      );
    } catch (e) {
      throw _map(e);
    }
  }

  /// The cancel did not happen: the server still holds the message, so the
  /// record goes back to what it was.
  Future<void> _restore(ScheduledEntry server) async {
    try {
      await _store.update(
        server.id,
        (c) =>
            c.mode == ScheduledMode.device && c.state == ScheduledState.failed
            ? server
            : null,
      );
    } catch (_) {}
  }
}
