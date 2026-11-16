// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/chat_page_harness.dart';
import 'utils/test_client.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(() async {
    await harness.tearDown();
    await AppSettings.sendTypingNotifications.setItem(true);
  });

  ChatController controllerOf(WidgetTester tester) =>
      tester.state<ChatController>(find.byType(ChatPageWithRoom));

  List<Event> events(WidgetTester tester) =>
      controllerOf(tester).timeline!.events;

  /// The room is encrypted, so the request body is ciphertext: the local echo
  /// carries what was composed.
  Map<String, Object?> echo(WidgetTester tester, int before, String body) {
    expect(events(tester).length, before + 1);
    return events(tester).firstWhere((e) => e.content['body'] == body).content;
  }

  Future<void> typeText(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('chat_input_field')), text);
    await harness.settle(tester, rounds: 2);
  }

  Future<void> selectWord(WidgetTester tester, String text, String word) async {
    await typeText(tester, text);
    final composer = controllerOf(tester).sendController;
    final start = text.indexOf(word);
    composer.value = composer.value.copyWith(
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + word.length,
      ),
    );
    await harness.settle(tester, rounds: 1);
  }

  testWidgets('bold through the panel is sent as one formatted event', (
    tester,
  ) async {
    await harness.open(tester);
    await selectWord(tester, 'hello world', 'world');
    await tester.tap(find.byKey(const Key('composer_format_toggle')));
    await harness.settle(tester, rounds: 1);
    await tester.tap(find.byKey(const ValueKey('format_bold')));
    await harness.settle(tester, rounds: 1);
    final before = events(tester).length;
    await tester.tap(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 12);
    final sent = echo(tester, before, 'hello **world**');
    expect(sent['format'], 'org.matrix.custom.html');
    expect(sent['formatted_body'], 'hello <strong>world</strong>');
    expect(sent['body'], 'hello **world**');
    final composer = controllerOf(tester).sendController;
    expect(composer.text, isEmpty);
    expect(composer.format.isEmpty, isTrue);
    await harness.finish(tester);
  });

  testWidgets('a list from the panel is sent and the composer resets', (
    tester,
  ) async {
    await harness.open(tester);
    await typeText(tester, 'item');
    final composer = controllerOf(tester).sendController;
    composer.value = composer.value.copyWith(
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.tap(find.byKey(const Key('composer_format_toggle')));
    await harness.settle(tester, rounds: 1);
    await tester.tap(find.byKey(const ValueKey('format_bullet')));
    await harness.settle(tester, rounds: 1);
    expect(composer.format.richIntent, isTrue);
    final before = events(tester).length;
    await tester.tap(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 12);
    final sent = echo(tester, before, '- item');
    expect(sent['formatted_body'], '<ul><li>item</li></ul>');
    expect(composer.text, isEmpty);
    expect(composer.format.richIntent, isFalse);
    expect(composer.canUndo, isFalse);
    await harness.finish(tester);
  });

  testWidgets('typed markdown still goes through the SDK path', (tester) async {
    await harness.open(tester);
    await typeText(tester, '**x** and more');
    final before = events(tester).length;
    await tester.tap(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 12);
    final sent = echo(tester, before, '**x** and more');
    expect(sent['formatted_body'], '<strong>x</strong> and more');
    expect(sent['body'], '**x** and more');
    await harness.finish(tester);
  });

  testWidgets('a command with formatting stays a command', (tester) async {
    await harness.open(tester);
    await selectWord(tester, '/me waves', 'waves');
    controllerOf(tester).sendController.toggleInline(RangeKind.bold);
    controllerOf(tester).sendController.format.richIntent = true;
    await harness.settle(tester, rounds: 1);
    final before = events(tester).length;
    await tester.tap(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 12);
    final sent = echo(tester, before, 'waves');
    expect(sent['msgtype'], 'm.emote');
    expect(sent['formatted_body'], isNot(contains('<strong>')));
    await harness.finish(tester);
  });

  testWidgets('a formatted message over the cap shows a notice and stays', (
    tester,
  ) async {
    await harness.open(tester);
    final text = '<' * 15000;
    await typeText(tester, text);
    final composer = controllerOf(tester).sendController;
    composer.value = composer.value.copyWith(
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    composer.toggleInline(RangeKind.bold);
    await harness.settle(tester, rounds: 1);
    final before = events(tester).length;
    await tester.tap(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 12);
    expect(
      find.text(
        'This formatted message is too long. Shorten it or remove some '
        'formatting.',
      ),
      findsOneWidget,
    );
    expect(events(tester).length, before);
    expect(composer.text, text);
    await tester.tap(find.text('Ok'));
    await harness.settle(tester, rounds: 1);
    await harness.finish(tester);
  });

  testWidgets('the draft keeps its formatting and comes back', (tester) async {
    await harness.open(tester);
    await selectWord(tester, 'hello world', 'world');
    controllerOf(tester).sendController.toggleInline(RangeKind.italic);
    controllerOf(tester).onInputBarChanged('hello world');
    await tester.pump(const Duration(milliseconds: 600));
    await harness.settle(tester, rounds: 2);
    final stored = DraftStore.of(harness.client).read(harness.room.id);
    expect(stored?.text, 'hello world');
    expect(stored?.format, isNotNull);
    await harness.finish(tester);

    await harness.open(tester);
    final composer = controllerOf(tester).sendController;
    expect(composer.text, 'hello world');
    expect(composer.format.ranges, [
      const FormatRange(6, 11, RangeKind.italic),
    ]);
    await harness.finish(tester);
  });

  testWidgets('a mark applied from the panel is saved in the draft', (
    tester,
  ) async {
    await harness.open(tester);
    await selectWord(tester, 'hello world', 'world');
    await tester.pump(const Duration(milliseconds: 700));
    DraftStore.of(harness.client).write(harness.room.id, '');
    controllerOf(tester).sendController.toggleInline(RangeKind.bold);
    await tester.pump(const Duration(milliseconds: 700));
    await harness.settle(tester, rounds: 2);
    final stored = DraftStore.of(harness.client).read(harness.room.id);
    expect(stored?.text, 'hello world');
    expect(stored?.format, isNotNull);
    await harness.finish(tester);
  });

  testWidgets('a hostile stored format restores the text only', (tester) async {
    DraftStore.of(harness.client).write(
      harness.room.id,
      'plain text',
      format: {
        'm': [
          [-1, 3, 0],
          [0, 999, 0],
          [0, 2, 6, 'javascript:alert(1)'],
        ],
      },
    );
    await harness.open(tester);
    final composer = controllerOf(tester).sendController;
    expect(composer.text, 'plain text');
    expect(composer.format.ranges, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('a formatted message over the event budget is refused', (
    tester,
  ) async {
    await harness.open(tester);
    final text = 'é' * 11000;
    await typeText(tester, text);
    final composer = controllerOf(tester).sendController;
    composer.value = composer.value.copyWith(
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    composer.toggleInline(RangeKind.bold);
    await harness.settle(tester, rounds: 1);
    expect(harness.room.encrypted, isTrue);
    final before = events(tester).length;
    await tester.tap(find.byKey(const Key('send_button')));
    await harness.settle(tester, rounds: 12);
    expect(
      find.text(
        'This formatted message is too long. Shorten it or remove some '
        'formatting.',
      ),
      findsOneWidget,
    );
    expect(events(tester).length, before);
    await tester.tap(find.text('Ok'));
    await harness.settle(tester, rounds: 1);
    await harness.finish(tester);
  });

  testWidgets('opening an edit never turns the edited text into a draft', (
    tester,
  ) async {
    await harness.open(tester);
    await typeText(tester, 'my real draft');
    await tester.pump(const Duration(milliseconds: 700));
    final controller = controllerOf(tester);
    final own = Event(
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': 'EDITED-MESSAGE-TEXT'},
      room: harness.room,
      eventId: r'$own-edit:example.org',
      senderId: harness.client.userID!,
      originServerTs: DateTime(2030, 1, 1, 12, 41),
    );
    controller.timeline!.events.insert(0, own);
    controller.selectedEvents.add(own);
    controller.editSelectedEventAction();
    await tester.pump(const Duration(milliseconds: 700));
    await harness.settle(tester, rounds: 2);
    expect(controller.sendController.text, 'EDITED-MESSAGE-TEXT');
    expect(
      DraftStore.of(harness.client).read(harness.room.id)?.text,
      'my real draft',
    );
    await typeText(tester, 'EDITED-MESSAGE-TEXT plus typing');
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      DraftStore.of(harness.client).read(harness.room.id)?.text,
      'my real draft',
    );
    controller.cancelReplyEventAction();
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.sendController.text, 'my real draft');
    expect(
      DraftStore.of(harness.client).read(harness.room.id)?.text,
      'my real draft',
    );
    await harness.finish(tester);
  });

  testWidgets('the draft goes to the account of the page, not the active one', (
    tester,
  ) async {
    await harness.open(tester);
    final other = (await tester.runAsync(
      () => prepareTestClient(clientName: 'draft-other-account'),
    ))!;
    DraftStore.forget(other);
    final matrix = tester.state<MatrixState>(find.byType(Matrix));
    matrix.widget.clients.add(other);
    matrix.setActiveClient(other, resetTabs: false);
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('chat_input_field')), findsOneWidget);
    await typeText(tester, 'typed on the first account');
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      DraftStore.of(harness.client).read(harness.room.id)?.text,
      'typed on the first account',
    );
    expect(DraftStore.of(other).read(harness.room.id), isNull);
    await harness.finish(tester);
  });

  testWidgets('Enter in a typed markdown list continues it at the caret', (
    tester,
  ) async {
    await AppSettings.sendOnEnter.setItem(false);
    await harness.open(tester);
    await typeText(tester, '- one\ntail');
    final composer = controllerOf(tester).sendController;
    composer.value = composer.value.copyWith(
      selection: const TextSelection.collapsed(offset: 5),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await harness.settle(tester, rounds: 1);
    expect(composer.text, '- one\n- \ntail');
    expect(composer.selection.baseOffset, 8);
    await AppSettings.sendOnEnter.setItem(true);
    await harness.finish(tester);
  });

  testWidgets('legacy drafts move before the slow account hooks finish', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_${harness.room.id}', 'legacy plaintext');
    final never = Completer<void>();
    MatrixState.accountHooks = (_, _, _) => never.future;
    await harness.open(tester);
    await harness.settle(tester, rounds: 4);
    expect(prefs.getString('draft_${harness.room.id}'), isNull);
    await harness.finish(tester);
  });

  testWidgets('leaving an edit after a formatting-only change asks first', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final own = Event(
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': 'plain words'},
      room: harness.room,
      eventId: r'$own-fmt:example.org',
      senderId: harness.client.userID!,
      originServerTs: DateTime(2030, 1, 1, 12, 41),
    );
    controller.timeline!.events.insert(0, own);
    controller.selectedEvents.add(own);
    controller.editSelectedEventAction();
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.byKey(const Key('chat_input_field')));
    await harness.settle(tester, rounds: 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 2);
    expect(controller.editEvent, isNull, reason: 'untouched edit just closes');

    controller.selectedEvents.add(own);
    controller.editSelectedEventAction();
    await harness.settle(tester, rounds: 2);
    final composer = controller.sendController;
    composer.value = composer.value.copyWith(
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    composer.toggleInline(RangeKind.bold);
    await tester.tap(find.byKey(const Key('chat_input_field')));
    await harness.settle(tester, rounds: 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await harness.settle(tester, rounds: 3);
    expect(find.text('Cancel'), findsOneWidget);
    expect(controller.editEvent, isNotNull);
    await tester.tap(find.text('Cancel'));
    await harness.settle(tester, rounds: 2);
    expect(controller.sendController.format.ranges, isNotEmpty);
    await harness.finish(tester);
  });
}
