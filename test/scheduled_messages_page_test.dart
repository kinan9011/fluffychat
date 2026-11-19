// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/scheduling/scheduled_messages_page.dart';
import 'package:odango/utils/scheduling/delayed_events_api.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';

import 'utils/golden.dart';
import 'utils/scheduling_fakes.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  SchedulingFixture? fixture;
  var serverMode = false;
  SchedulingFixture f() =>
      fixture ??= SchedulingFixture(client, room, serverSupported: serverMode);
  const size = Size(400, 760);

  setUpAll(() async {
    client = await prepareTestClient(clientName: 'sched-page');
    room = Room(id: '!design:example.org', client: client);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Design crew'},
        room: room,
        eventId: r'$name:example.org',
        senderId: '@test:fakeServer.notExisting',
        originServerTs: DateTime(2025),
      ),
    );
    client.rooms.add(room);
  });

  setUp(() {
    ScheduledStore.revision.value = 0;
    fixture = null;
    serverMode = false;
  });
  tearDown(() => fixture?.dispose());

  Future<void> put(WidgetTester tester, ScheduledEntry entry) async {
    final done = f().store.put(entry);
    await tester.pump();
    await done;
  }

  Future<void> addThree(WidgetTester tester) async {
    await put(
      tester,
      f().entry(
        'entry-aaaa0001',
        'Standup moved to 10:00 today, same link.',
        at: DateTime(2025, 11, 14, 9),
      ),
    );
    await put(
      tester,
      f().entry(
        'entry-aaaa0002',
        'Reminder: release notes are due before lunch.',
        at: DateTime(2025, 11, 14, 11, 30),
      ),
    );
    await put(
      tester,
      f().entry(
        'entry-aaaa0003',
        'Happy launch week, everyone. Retro is on Thursday.',
        at: DateTime(2025, 11, 17, 9),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool rtl = false,
    Locale locale = const Locale('en'),
    Room? inRoom,
  }) async {
    await pumpGoldenWidget(
      tester,
      ScheduledMessagesBody(
        key: UniqueKey(),
        room: inRoom ?? room,
        messages: f().messages,
        now: () => f().now,
      ),
      brightness: brightness,
      rtl: rtl,
      locale: locale,
      size: size,
      settle: false,
    );
    if (locale.languageCode != 'en') {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Finder bubble(String id) => find.byKey(ValueKey('scheduled_$id'));

  testWidgets('without scheduled messages: the empty state', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('scheduled_empty')), findsOneWidget);
    expect(find.text('No scheduled messages'), findsOneWidget);
    expect(find.text('0 in Design crew'), findsOneWidget);
  });

  Future<void> addMany(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await put(
        tester,
        f().entry(
          'entry-bulk${i.toString().padLeft(4, '0')}',
          'Scheduled text number $i',
          at: DateTime(2025, 11, 14 + i % 3, 9, i),
        ),
      );
    }
  }

  testWidgets('30 rows cost no more blur than 3 (glass budget, W13)', (
    tester,
  ) async {
    await addMany(tester, 3);
    await open(tester);
    final few = find.byType(BackdropFilter).evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await addMany(tester, 27);
    await open(tester);
    expect(find.byType(BackdropFilter).evaluate().length, few);
    expect(few, lessThanOrEqualTo(4));
  });

  testWidgets('the lite glass mode blurs nothing on the page', (tester) async {
    await AppSettings.glassMode.setItem('lite');
    addTearDown(() => AppSettings.glassMode.setItem('auto'));
    await addMany(tester, 5);
    await open(tester);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('messages are grouped by day with their time', (tester) async {
    await addThree(tester);
    await open(tester);
    expect(find.text('Sending on Fri, Nov 14'), findsOneWidget);
    expect(find.text('Sending on Mon, Nov 17'), findsOneWidget);
    expect(
      find.text('Standup moved to 10:00 today, same link.'),
      findsOneWidget,
    );
    expect(find.text('3 in Design crew'), findsOneWidget);
    expect(find.text('9:00 AM'), findsNWidgets(2));
    expect(find.text('11:30 AM'), findsOneWidget);
    final first = tester.getTopLeft(bubble('entry-aaaa0001')).dy;
    final last = tester.getTopLeft(bubble('entry-aaaa0003')).dy;
    expect(first, lessThan(last));
  });

  testWidgets('a tap selects, a second tap deselects', (tester) async {
    await addThree(tester);
    await open(tester);
    expect(find.byKey(const Key('scheduled_send_now')), findsNothing);
    await tester.tap(find.text('Standup moved to 10:00 today, same link.'));
    await tester.pump();
    expect(find.byKey(const Key('scheduled_send_now')), findsOneWidget);
    expect(find.byKey(const Key('scheduled_reschedule')), findsOneWidget);
    expect(find.byKey(const Key('scheduled_delete')), findsOneWidget);
    await tester.tap(find.text('Standup moved to 10:00 today, same link.'));
    await tester.pump();
    expect(find.byKey(const Key('scheduled_send_now')), findsNothing);
  });

  testWidgets('send now hands the message over and drops it from the list', (
    tester,
  ) async {
    await addThree(tester);
    await open(tester);
    await tester.tap(find.text('Standup moved to 10:00 today, same link.'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scheduled_send_now')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(f().sent.single['body'], 'Standup moved to 10:00 today, same link.');
    expect(find.text('Standup moved to 10:00 today, same link.'), findsNothing);
    expect(find.text('2 in Design crew'), findsOneWidget);
  });

  testWidgets('delete asks first, cancel keeps the message', (tester) async {
    await addThree(tester);
    await open(tester);
    await tester.tap(find.text('Standup moved to 10:00 today, same link.'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scheduled_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this scheduled message?'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('ok_cancel_alert_dialog_cancel_button')),
    );
    await tester.pumpAndSettle();
    expect(f().store.entries(), hasLength(3));
    expect(
      find.text('Standup moved to 10:00 today, same link.'),
      findsOneWidget,
    );
  });

  testWidgets('delete then ok removes it', (tester) async {
    await addThree(tester);
    await open(tester);
    await tester.tap(find.text('Standup moved to 10:00 today, same link.'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scheduled_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ok_cancel_alert_dialog_ok_button')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      f().store.entries().map((e) => e.id),
      isNot(contains('entry-aaaa0001')),
    );
    expect(find.text('Standup moved to 10:00 today, same link.'), findsNothing);
  });

  testWidgets('reschedule opens the sheet at the message time', (tester) async {
    await addThree(tester);
    await open(tester);
    await tester.tap(
      find.text('Happy launch week, everyone. Retro is on Thursday.'),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('scheduled_reschedule')));
    await tester.pumpAndSettle();
    expect(find.text('Schedule for Mon, Nov 17, 9:00 AM'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule_confirm')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    final moved = f().store.entries().firstWhere(
      (e) => e.id == 'entry-aaaa0003',
    );
    expect(moved.sendAt, DateTime(2025, 11, 14, 9));
    expect(find.text('Sending on Mon, Nov 17'), findsNothing);
    f().queue.stop();
  });

  testWidgets('a message that was not sent says so and can be retried', (
    tester,
  ) async {
    await put(
      tester,
      f().entry(
        'entry-aaaa0001',
        'Missed one',
        at: DateTime(2025, 11, 13, 9),
        state: ScheduledState.failed,
        reason: ScheduledFailure.late,
      ),
    );
    await open(tester);
    expect(
      find.text("Not sent: Odango wasn't running at 9:00 AM"),
      findsOneWidget,
    );
    await tester.tap(find.text('Missed one'));
    await tester.pump();
    expect(find.byKey(const Key('scheduled_send_now')), findsOneWidget);
    expect(find.byKey(const Key('scheduled_reschedule')), findsOneWidget);
  });

  testWidgets('every failure says what really happened', (tester) async {
    final reasons = {
      ScheduledFailure.late: "Not sent: Odango wasn't running at 9:00 AM",
      ScheduledFailure.sendFailed:
          'Not sent: sending failed or was interrupted. Check the chat before '
          'you send it again.',
      ScheduledFailure.roomUnavailable:
          'Not sent: you are no longer in this chat.',
      ScheduledFailure.rescheduleFailed:
          'Not rescheduled: the new time could not be set. The message is '
          'kept here, reschedule it or send it now.',
    };
    var n = 1;
    for (final reason in reasons.keys) {
      await put(
        tester,
        f().entry(
          'entry-aaaa000${n++}',
          'Text ${reason.name}',
          at: DateTime(2025, 11, 13, 9),
          state: ScheduledState.failed,
          reason: reason,
        ),
      );
    }
    await open(tester);
    for (final text in reasons.values) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining("wasn't running"), findsOneWidget);
  });

  testWidgets('a when-online message that expired says why', (tester) async {
    await put(
      tester,
      f().entry(
        'entry-aaaa0001',
        'ping',
        untilOnline: '@mara:example.org',
        state: ScheduledState.failed,
        reason: ScheduledFailure.expired,
      ),
    );
    await open(tester);
    expect(
      find.text('Not sent: they did not come online within 30 days.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed message without a stored reason is a send failure', (
    tester,
  ) async {
    await put(
      tester,
      f().entry(
        'entry-aaaa0001',
        'Missed one',
        at: DateTime(2025, 11, 13, 9),
        state: ScheduledState.failed,
      ),
    );
    await open(tester);
    expect(find.textContaining("Odango wasn't running"), findsNothing);
    expect(
      find.textContaining('sending failed or was interrupted'),
      findsOneWidget,
    );
  });

  testWidgets('the device banner shows for messages this device sends', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('scheduled_device_banner')), findsNothing);
    await put(
      tester,
      f().entry('entry-aaaa0001', 'hi', at: DateTime(2025, 11, 14, 9)),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduled_device_banner')), findsOneWidget);
    expect(find.textContaining('Keep Odango running'), findsOneWidget);
  });

  testWidgets('a when-online message is grouped by the person, no reschedule', (
    tester,
  ) async {
    await put(
      tester,
      f().entry('entry-aaaa0001', 'ping', untilOnline: '@mara:example.org'),
    );
    await open(tester);
    expect(find.text('When Mara is online'), findsOneWidget);
    await tester.tap(find.text('ping'));
    await tester.pump();
    expect(find.byKey(const Key('scheduled_send_now')), findsOneWidget);
    expect(find.byKey(const Key('scheduled_reschedule')), findsNothing);
  });

  group('messages another device scheduled', () {
    final at = DateTime(2025, 11, 14, 9);

    ServerDelayedEvent server(
      String id,
      String type,
      Map<String, Object?> content,
    ) => ServerDelayedEvent(
      delayId: id,
      roomId: room.id,
      type: type,
      sendAt: at,
      content: content,
    );

    setUp(() => serverMode = true);

    testWidgets('its text is shown as plain text, nothing is interpreted', (
      tester,
    ) async {
      f().api.listed.add(
        server('d-one', 'm.room.message', {
          'msgtype': 'm.text',
          'body':
              '<b>bold</b> <script>alert(1)</script> [link](https://evil.example)',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<img src=x onerror=alert(1)>',
        }),
      );
      await open(tester);
      expect(
        find.text(
          '<b>bold</b> <script>alert(1)</script> [link](https://evil.example)',
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('Scheduled on another device'), findsOneWidget);
    });

    testWidgets('the delay id is in no widget key', (tester) async {
      f().api.listed.add(
        server('SENTINEL-DELAY-ID', 'm.room.message', {
          'msgtype': 'm.text',
          'body': 'from elsewhere',
        }),
      );
      await open(tester);
      expect(find.text('from elsewhere'), findsOneWidget);
      for (final widget in tester.allWidgets) {
        expect('${widget.key}', isNot(contains('SENTINEL-DELAY-ID')));
      }
    });

    testWidgets('bidi and control characters are removed', (tester) async {
      f().api.listed.add(
        server('d-two', 'm.room.message', {
          'msgtype': 'm.text',
          'body': 'safe\u202Etxet\u0000end',
        }),
      );
      await open(tester);
      expect(find.text('safe txet end'), findsOneWidget);
    });

    testWidgets('an encrypted one has no text and cannot be rescheduled', (
      tester,
    ) async {
      f().api.listed.add(
        server('d-three', 'm.room.encrypted', {'ciphertext': 'x'}),
      );
      await open(tester);
      expect(find.text('Scheduled on another device'), findsOneWidget);
      await tester.tap(find.text('Scheduled on another device'));
      await tester.pump();
      expect(find.byKey(const Key('scheduled_send_now')), findsOneWidget);
      expect(find.byKey(const Key('scheduled_reschedule')), findsNothing);
      expect(find.byKey(const Key('scheduled_delete')), findsOneWidget);
    });

    testWidgets('a server that cannot be reached is said so, retry works', (
      tester,
    ) async {
      f().api.listError = StateError('offline');
      await put(
        tester,
        f().entry('entry-aaaa0001', 'kept', at: at, mode: ScheduledMode.server),
      );
      await open(tester);
      expect(find.byKey(const Key('scheduled_load_failed')), findsOneWidget);
      expect(find.text('kept'), findsOneWidget, reason: 'local text stays');
      f().api.listError = null;
      f().api.listed.add(
        ServerDelayedEvent(
          delayId: 'delay-entry-aaaa0001',
          roomId: room.id,
          type: 'm.room.message',
          sendAt: at,
          content: const {'body': 'kept'},
        ),
      );
      await tester.tap(find.text('Try again'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scheduled_load_failed')), findsNothing);
    });
  });

  group('after the server or the queue sent it', () {
    setUp(() => serverMode = true);

    testWidgets('a reschedule says it was already sent, nothing is scheduled', (
      tester,
    ) async {
      await put(
        tester,
        f().entry(
          'entry-aaaa0001',
          'gone already',
          at: DateTime(2025, 11, 14, 9),
          mode: ScheduledMode.server,
        ),
      );
      f().api.listed.add(
        ServerDelayedEvent(
          delayId: 'delay-entry-aaaa0001',
          roomId: room.id,
          type: 'm.room.message',
          sendAt: DateTime(2025, 11, 14, 9),
          content: const {'body': 'gone already'},
        ),
      );
      f().api.cancelError = MatrixException.fromJson(const {
        'errcode': 'M_NOT_FOUND',
        'error': 'x',
      });
      await open(tester);
      await tester.tap(find.text('gone already'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('scheduled_reschedule')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('schedule_preset_tomorrowMorning')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule_confirm')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This message was already sent or was cancelled on another device.',
        ),
        findsOneWidget,
      );
      expect(f().api.log, isNot(contains('schedule')));
      expect(f().store.entries(), isEmpty);
    });

    testWidgets('a plain record in a room that is encrypted by now is marked', (
      tester,
    ) async {
      final encrypted = Room(id: '!crypt:example.org', client: client);
      encrypted.setState(
        Event(
          type: EventTypes.Encryption,
          stateKey: '',
          content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
          room: encrypted,
          eventId: r'$enc:example.org',
          senderId: '@test:fakeServer.notExisting',
          originServerTs: DateTime(2025),
        ),
      );
      client.rooms.add(encrypted);
      addTearDown(() => client.rooms.remove(encrypted));
      fixture = SchedulingFixture(client, encrypted, serverSupported: true);
      await put(
        tester,
        f().entry(
          'entry-aaaa0001',
          'sent in the clear',
          at: DateTime(2025, 11, 14, 9),
          mode: ScheduledMode.server,
        ),
      );
      f().api.listed.add(
        ServerDelayedEvent(
          delayId: 'delay-entry-aaaa0001',
          roomId: encrypted.id,
          type: 'm.room.message',
          sendAt: DateTime(2025, 11, 14, 9),
          content: const {'body': 'sent in the clear'},
        ),
      );
      await open(tester, inRoom: encrypted);
      expect(
        find.text(
          'Will be sent unencrypted: this chat was encrypted after you '
          'scheduled it. Reschedule it to encrypt it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('sent in the clear'));
      await tester.pump();
      expect(find.byKey(const Key('scheduled_send_now')), findsOneWidget);
      expect(find.byKey(const Key('scheduled_reschedule')), findsOneWidget);
      expect(find.byKey(const Key('scheduled_delete')), findsOneWidget);
    });
  });

  testWidgets(
    'a burst of changes asks the server one more time, not for each',
    (tester) async {
      serverMode = true;
      await put(
        tester,
        f().entry(
          'entry-aaaa0001',
          'kept',
          at: DateTime(2025, 11, 14, 9),
          mode: ScheduledMode.server,
        ),
      );
      f().api.listed.add(
        ServerDelayedEvent(
          delayId: 'delay-entry-aaaa0001',
          roomId: room.id,
          type: 'm.room.message',
          sendAt: DateTime(2025, 11, 14, 9),
          content: const {'body': 'kept'},
        ),
      );
      await open(tester);
      final before = f().api.log.where((l) => l == 'list').length;
      for (var i = 0; i < 4; i++) {
        ScheduledStore.revision.value++;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      final lists = f().api.log.where((l) => l == 'list').length - before;
      expect(lists, lessThanOrEqualTo(2));
      expect(lists, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('touch targets are at least 44 high', (tester) async {
    await addThree(tester);
    await open(tester);
    await tester.tap(find.text('Standup moved to 10:00 today, same link.'));
    await tester.pump();
    for (final key in [
      'scheduled_send_now',
      'scheduled_reschedule',
      'scheduled_delete',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
    }
    expect(
      tester.getSize(bubble('entry-aaaa0001')).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byKey(const Key('scheduled_back'))).shortestSide,
      greaterThanOrEqualTo(AppChat.headerButton - 4),
    );
  });

  testWidgets('bubbles are right aligned and at most 82 percent wide', (
    tester,
  ) async {
    await addThree(tester);
    await open(tester);
    final rect = tester.getRect(
      find
          .descendant(
            of: bubble('entry-aaaa0001'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(rect.width, lessThanOrEqualTo(size.width * 0.82 + 0.5));
    expect(rect.right, closeTo(size.width - 10, 1));
  });

  testWidgets('goldens', (tester) async {
    for (final variant in goldenVariants) {
      fixture?.dispose();
      fixture = null;
      await put(
        tester,
        f().entry(
          'entry-aaaa0001',
          'Standup moved to 10:00 today, same link.',
          at: DateTime(2025, 11, 14, 9),
        ),
      );
      await put(
        tester,
        f().entry(
          'entry-aaaa0002',
          'Reminder: release notes are due before lunch.',
          at: DateTime(2025, 11, 14, 11, 30),
        ),
      );
      await put(
        tester,
        f().entry(
          'entry-aaaa0003',
          'Happy launch week, everyone. Retro is on Thursday.',
          at: DateTime(2025, 11, 17, 9),
        ),
      );
      await open(
        tester,
        brightness: variant.brightness,
        rtl: variant.rtl,
        locale: variant.locale,
      );
      await tester.tap(
        find.text('Happy launch week, everyone. Retro is on Thursday.'),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/scheduled_messages_${variant.suffix}.png'),
      );
    }
  });
}
