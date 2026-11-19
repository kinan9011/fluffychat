// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';

import 'utils/chat_page_harness.dart';

ScheduledEntry _entry(
  String id, {
  ScheduledMode mode = ScheduledMode.server,
  String? delayId,
  ScheduledState state = ScheduledState.pending,
}) => ScheduledEntry(
  id: id,
  roomId: '!room:example.org',
  mode: mode,
  sendAt: DateTime.now().add(const Duration(hours: 2)),
  createdAt: DateTime.now(),
  delayId: delayId,
  state: state,
  content: const {'msgtype': 'm.text', 'body': 'hi'},
);

void main() {
  final harness = ChatPageHarness();
  final added = <String>[];

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
  });
  tearDown(() async {
    final store = ScheduledStore.of(harness.client);
    await harness.tearDown();
    for (final id in added) {
      unawaited(store.remove(id));
    }
    added.clear();
  });

  Future<void> put(WidgetTester? tester, ScheduledEntry entry) async {
    added.add(entry.id);
    Future<void> write() => ScheduledStore.of(harness.client).put(entry);
    if (tester == null) return write();
    await tester.runAsync(write);
  }

  Future<void> tapLogout(WidgetTester tester) async {
    await harness.open(tester, path: '/settings', height: 1800);
    await tester.tap(find.text('Logout'));
    await harness.settle(tester, rounds: 6);
  }

  testWidgets('the count of server-held messages is in the confirmation', (
    tester,
  ) async {
    await put(tester, _entry('held-one-1', delayId: 'delay1'));
    await put(tester, _entry('held-two-2', delayId: 'delay2'));
    await tapLogout(tester);
    expect(
      find.textContaining(
        '2 scheduled messages are held by your server and will still be sent',
      ),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets('one held message uses the singular', (tester) async {
    await put(tester, _entry('held-one-1', delayId: 'delay1'));
    await tapLogout(tester);
    expect(
      find.textContaining('1 scheduled message is held by your server'),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets('messages kept on this device or failed are not counted', (
    tester,
  ) async {
    await put(tester, _entry('device-only-1', mode: ScheduledMode.device));
    await put(
      tester,
      _entry('failed-one-1', delayId: 'delay3', state: ScheduledState.failed),
    );
    await tapLogout(tester);
    expect(find.textContaining('scheduled message'), findsNothing);
    expect(find.byKey(const Key('ok_cancel_alert_dialog_ok_button')), findsOne);
    await harness.finish(tester);
  });

  testWidgets('with nothing scheduled the confirmation is unchanged', (
    tester,
  ) async {
    await tapLogout(tester);
    expect(find.textContaining('held by your server'), findsNothing);
    await harness.finish(tester);
  });

  test('serverHeldCount counts only pending server-held entries', () async {
    final store = ScheduledStore.of(harness.client);
    await store.ready;
    final before = store.serverHeldCount;
    await put(null, _entry('held-one-1', delayId: 'delay1'));
    await put(null, _entry('device-only-1', mode: ScheduledMode.device));
    expect(store.serverHeldCount, before + 1);
  });
}
