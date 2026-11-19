// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/scheduling/schedule_labels.dart';
import 'package:odango/pages/chat/scheduling/schedule_sheet.dart';
import 'package:odango/pages/chat/scheduling/scheduled_messages_view.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/scheduling/scheduled_messages.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';
import 'package:odango/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:odango/widgets/matrix.dart';

/// Route `/rooms/:roomid/scheduled`.
class ScheduledMessagesPage extends StatelessWidget {
  const ScheduledMessagesPage({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final room = matrix.client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }
    return ScheduledMessagesBody(
      key: ValueKey('scheduled_${room.client.clientName}_$roomId'),
      room: room,
      messages: ScheduledMessages.of(room.client, matrix.serverCapabilities),
    );
  }
}

class ScheduledMessagesBody extends StatefulWidget {
  const ScheduledMessagesBody({
    required this.room,
    required this.messages,
    this.now,
    super.key,
  });

  final Room room;
  final ScheduledMessages messages;

  @visibleForTesting
  final DateTime Function()? now;

  @override
  State<ScheduledMessagesBody> createState() => ScheduledMessagesController();
}

class ScheduledMessagesController extends State<ScheduledMessagesBody> {
  static const maxRefresh = Duration(minutes: 1);

  ScheduledList? list;
  String? selectedKey;
  Timer? _timer;

  Room get room => widget.room;
  ScheduledMessages get messages => widget.messages;

  DateTime now() => (widget.now ?? DateTime.now)();

  List<ScheduledItem> get items => list?.items ?? const [];

  ScheduledItem? get selected =>
      items.where((i) => i.key == selectedKey).firstOrNull;

  String nameOf(String userId) =>
      room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();

  @override
  void initState() {
    super.initState();
    ScheduledStore.revision.addListener(refresh);
    unawaited(refresh());
  }

  @override
  void dispose() {
    ScheduledStore.revision.removeListener(refresh);
    _timer?.cancel();
    super.dispose();
  }

  var _refreshing = false;
  var _refreshAgain = false;

  /// One request at a time: a change that arrives meanwhile asks for one more
  /// round afterwards (homeservers rate limit these requests).
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final result = await messages.load(room);
        if (!mounted) return;
        setState(() {
          list = result;
          if (selected == null) selectedKey = null;
        });
        _arm(result);
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  void _arm(ScheduledList result) {
    _timer?.cancel();
    final times = [
      for (final item in result.items)
        if (item.onServer && item.sendAt != null) item.sendAt!,
    ]..sort();
    if (times.isEmpty) return;
    final wait = times.first.difference(now()) + const Duration(seconds: 2);
    _timer = Timer(
      wait.isNegative || wait > maxRefresh ? maxRefresh : wait,
      () => unawaited(refresh()),
    );
  }

  void select(ScheduledItem item) =>
      setState(() => selectedKey = selectedKey == item.key ? null : item.key);

  Future<void> _run(Future<void> Function() action) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ScheduleException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(scheduleErrorMessage(l10n, e))),
      );
    }
    if (mounted) await refresh();
  }

  Future<void> sendNow() async {
    final item = selected;
    if (item == null) return;
    await _run(() => messages.sendNow(item));
  }

  Future<void> reschedule() async {
    final item = selected;
    if (item == null || !item.canReschedule) return;
    final mode = await messages.modeFor();
    if (!mounted) return;
    final at = await showScheduleSheet(
      context,
      preview: safeDisplayText(item.preview, maxGraphemes: 120),
      mode: mode,
      encrypted: room.encrypted,
      initial: item.sendAt,
      now: widget.now,
    );
    if (at == null) return;
    await _run(() => messages.reschedule(item, at));
  }

  Future<void> delete() async {
    final item = selected;
    if (item == null) return;
    final l10n = L10n.of(context);
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: l10n.scheduledDeleteConfirm,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok) return;
    await _run(() => messages.delete(item));
  }

  @override
  Widget build(BuildContext context) => ScheduledMessagesView(this);
}
