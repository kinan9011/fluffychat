// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/utils/status/status_clear_store.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);
  const userId = '@test:fakeServer.notExisting';

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
    api.getOverrides.clear();
    api.onRequest = null;
  });
  tearDown(harness.tearDown);

  Future<void> openSheet(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
  }) async {
    await harness.open(tester, path: '/settings', width: width, height: height);
    final row = find.byKey(const ValueKey('settings_set_status'));
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await harness.settle(tester);
  }

  List<RecordedRequest> puts() => api.requests('/presence/', method: 'PUT');
  Map<Object?, Object?> lastPut() => puts().last.json! as Map;

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await harness.settle(tester, rounds: 3);
  }

  testWidgets('a suggestion fills the field', (tester) async {
    await openSheet(tester);
    await tapKey(tester, 'status_suggestion_meeting');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('status_field')),
    );
    expect(field.controller!.text, 'In a meeting');
    await harness.finish(tester);
  });

  testWidgets('hidden by default: the status goes out as offline', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('status_field')),
      'On holiday until Monday',
    );
    await tapKey(tester, 'status_save');
    expect(lastPut()['status_msg'], 'On holiday until Monday');
    expect(lastPut()['presence'], 'offline');
    expect(AppSettings.shareOnlineStatus.value, isFalse);
    await harness.finish(tester);
  });

  testWidgets('choosing Online shows the note and only Save changes settings', (
    tester,
  ) async {
    await openSheet(tester);
    await tapKey(tester, 'status_presence_online');
    expect(find.byKey(const ValueKey('status_sharing_note')), findsOneWidget);
    expect(AppSettings.shareOnlineStatus.value, isFalse);
    expect(
      puts().where((r) => (r.json! as Map)['presence'] == 'online'),
      isEmpty,
    );
    await tapKey(tester, 'status_save');
    expect(AppSettings.shareOnlineStatus.value, isTrue);
    expect(AppSettings.appearOffline.value, isFalse);
    expect(AppSettings.presenceAway.value, isFalse);
    expect(lastPut()['presence'], 'online');
    await harness.finish(tester);
  });

  testWidgets('choosing Away is published as unavailable', (tester) async {
    await openSheet(tester);
    await tapKey(tester, 'status_presence_away');
    await tapKey(tester, 'status_save');
    expect(AppSettings.presenceAway.value, isTrue);
    expect(AppSettings.shareOnlineStatus.value, isTrue);
    expect(lastPut()['presence'], 'unavailable');
    await harness.finish(tester);
  });

  testWidgets('Appear offline wins over a shared status', (tester) async {
    await AppSettings.shareOnlineStatus.setItem(true);
    await openSheet(tester);
    await tapKey(tester, 'status_presence_appearOffline');
    await tester.enterText(find.byKey(const ValueKey('status_field')), 'Busy');
    await tapKey(tester, 'status_save');
    expect(AppSettings.appearOffline.value, isTrue);
    expect(lastPut()['presence'], 'offline');
    await harness.finish(tester);
  });

  testWidgets('Clear sends an empty status and forgets the deadline', (
    tester,
  ) async {
    await StatusClearStore().arm(
      userId,
      'Old',
      DateTime.now().add(const Duration(hours: 1)),
    );
    await openSheet(tester);
    await tapKey(tester, 'status_clear');
    expect(lastPut()['status_msg'], '');
    expect(StatusClearStore().recordFor(userId), isNull);
    await harness.finish(tester);
  });

  group('a due status is cleared when the app starts', () {
    Future<void> startWithDueStatus(
      WidgetTester tester,
      AppLifecycleState state,
    ) async {
      await AppSettings.shareOnlineStatus.setItem(true);
      api.getOverrides['/status'] = {
        'presence': 'online',
        'status_msg': 'Old status',
      };
      await StatusClearStore().arm(
        userId,
        'Old status',
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      tester.binding.handleAppLifecycleStateChanged(state);
      try {
        await harness.open(tester, path: '/settings');
        await harness.settle(tester, rounds: 8);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    }

    List<Object?> clears() => [
      for (final put in puts())
        if ((put.json! as Map)['status_msg'] == '')
          (put.json! as Map)['presence'],
    ];

    testWidgets('in the foreground a visible user stays online', (
      tester,
    ) async {
      await startWithDueStatus(tester, AppLifecycleState.resumed);
      expect(clears(), ['online']);
      await harness.finish(tester);
    });

    testWidgets('not in the foreground nothing says online', (tester) async {
      await startWithDueStatus(tester, AppLifecycleState.inactive);
      expect(clears(), ['unavailable']);
      await harness.finish(tester);
    });
  });

  testWidgets('clear after one hour arms the store with the text', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('status_field')), 'Focus');
    await tapKey(tester, 'status_clear_hour');
    await tapKey(tester, 'status_save');
    final record = StatusClearStore().recordFor(userId);
    expect(record?.message, 'Focus');
    final delta = record!.clearAtMs - DateTime.now().millisecondsSinceEpoch;
    expect(delta, inInclusiveRange(59 * 60 * 1000, 61 * 60 * 1000));
    await harness.finish(tester);
  });

  testWidgets('never leaves no deadline behind', (tester) async {
    await StatusClearStore().arm(
      userId,
      'Old',
      DateTime.now().add(const Duration(hours: 1)),
    );
    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('status_field')), 'New');
    await tapKey(tester, 'status_save');
    expect(StatusClearStore().recordFor(userId), isNull);
    await harness.finish(tester);
  });

  testWidgets('hostile text is sanitised before it is sent', (tester) async {
    await openSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('status_field')),
      'a\u202Eb\u0000c\u2066d',
    );
    await tapKey(tester, 'status_save');
    expect(lastPut()['status_msg'], 'a b c d');
    await harness.finish(tester);
  });

  testWidgets('an empty field clears the status', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('status_field')), '   ');
    await tapKey(tester, 'status_save');
    expect(lastPut()['status_msg'], '');
    await harness.finish(tester);
  });

  testWidgets('the current status is shown when the sheet opens', (
    tester,
  ) async {
    api.getOverrides['/status'] = {
      'presence': 'online',
      'status_msg': 'Already set',
    };
    await openSheet(tester);
    await harness.settle(tester, rounds: 4);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('status_field')),
    );
    expect(field.controller!.text, 'Already set');
    await harness.finish(tester);
  });

  testWidgets('320x480 with the keyboard open: no overflow, Save reachable', (
    tester,
  ) async {
    await openSheet(tester, width: 320, height: 480);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const ValueKey('status_field')));
    await harness.settle(tester, rounds: 3);
    expect(tester.takeException(), isNull);
    final save = find.byKey(const ValueKey('status_save'));
    expect(save, findsOneWidget);
    expect(tester.getBottomLeft(save).dy, lessThanOrEqualTo(480 - 260 + 1));
    await harness.finish(tester);
  });
}
