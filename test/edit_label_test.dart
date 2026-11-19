// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/edit_history_sheet.dart';
import 'package:odango/pages/chat/events/message_footer.dart';
import 'package:odango/pages/chat/message_action_runner.dart';
import 'package:odango/utils/chat/message_actions.dart';
import 'package:odango/utils/chat/message_ticks.dart';
import 'package:odango/widgets/glass_menu.dart';

import 'utils/chat_page_harness.dart';
import 'utils/golden.dart';

void main() {
  group('MessageFooter', () {
    Widget footer({bool edited = true, VoidCallback? onTap}) => MessageFooter(
      time: '12:44',
      edited: edited,
      tick: Tick.none,
      color: Colors.black,
      onEditedTap: onTap,
    );

    testWidgets('the edited label is underlined and opens the history', (
      tester,
    ) async {
      var taps = 0;
      await pumpGoldenWidget(tester, footer(onTap: () => taps++));
      final text = tester.widget<Text>(find.text('(edited)'));
      expect(text.style?.decoration, TextDecoration.underline);
      await tester.tap(find.byKey(const ValueKey('edited_label')));
      expect(taps, 1);
    });

    testWidgets('it is a labelled button for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGoldenWidget(tester, footer(onTap: () {}));
      final semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('edited_label')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.label, 'Edit history');
      handle.dispose();
    });

    testWidgets('without a callback it is plain text, not a target', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, footer());
      expect(find.byKey(const ValueKey('edited_label')), findsNothing);
      final text = tester.widget<Text>(find.text('(edited)'));
      expect(text.style?.decoration, isNot(TextDecoration.underline));
    });

    testWidgets('a message that was not edited shows no label', (tester) async {
      await pumpGoldenWidget(tester, footer(edited: false, onTap: () {}));
      expect(find.text('(edited)'), findsNothing);
      expect(find.byKey(const ValueKey('edited_label')), findsNothing);
    });
  });

  group('message actions', () {
    test('the history entry sits before info and only when offered', () {
      expect(
        availableMessageActions(
          const MessageActionContext(canReply: true, canViewHistory: true),
        ),
        [
          MessageAction.reply,
          MessageAction.select,
          MessageAction.editHistory,
          MessageAction.info,
        ],
      );
      expect(
        availableMessageActions(const MessageActionContext(canReply: true)),
        [MessageAction.reply, MessageAction.select, MessageAction.info],
      );
    });
  });

  group('in the chat', () {
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

    var counter = 0;
    Event make(String body, {String? sender, Map<String, Object?>? content}) =>
        Event(
          type: EventTypes.Message,
          content: content ?? {'msgtype': MessageTypes.Text, 'body': body},
          room: harness.room,
          eventId: '\$h${counter++}:example.org',
          senderId: sender ?? harness.client.userID!,
          originServerTs: DateTime(2030, 1, 1, 12, 41),
        );

    Future<(ChatController, Event)> openEdited(WidgetTester tester) async {
      final original = make('Testing it now, results in an hour.');
      final edit = Event(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Text,
          'body': '* Testing it now, results in 20 minutes.',
          'm.new_content': {
            'msgtype': MessageTypes.Text,
            'body': 'Testing it now, results in 20 minutes.',
          },
          'm.relates_to': {
            'rel_type': RelationshipTypes.edit,
            'event_id': original.eventId,
          },
        },
        room: harness.room,
        eventId: '\$edit${counter++}:example.org',
        senderId: original.senderId,
        originServerTs: DateTime(2030, 1, 1, 12, 43),
      );
      await harness.open(tester);
      final controller = controllerOf(tester);
      controller.timeline!.aggregatedEvents[original.eventId] = {
        RelationshipTypes.edit: {edit},
      };
      controller.timeline!.events.insert(0, original);
      controller.updateView();
      await harness.settle(tester, rounds: 3);
      return (controller, original);
    }

    testWidgets('tapping (edited) shows the versions of the message', (
      tester,
    ) async {
      await openEdited(tester);
      FakeMatrixApi.calledEndpoints.clear();
      await tester.tap(find.byKey(const ValueKey('edited_label')));
      await harness.settle(tester, rounds: 6);
      expect(find.byType(EditHistorySheet), findsOneWidget);
      expect(find.text('Edit history'), findsOneWidget);
      expect(find.textContaining('CURRENT'), findsOneWidget);
      expect(find.textContaining('ORIGINAL'), findsOneWidget);
      expect(
        find.text('Testing it now, results in 20 minutes.', findRichText: true),
        findsWidgets,
      );
      final keys = FakeMatrixApi.calledEndpoints.keys.toList();
      expect(keys.where((k) => k.contains('/relations/')), hasLength(1));
      for (final forbidden in [
        'receipt',
        'typing',
        'presence',
        'read_markers',
      ]) {
        expect(keys.where((k) => k.contains(forbidden)), isEmpty);
      }
      await tester.tap(find.byKey(const ValueKey('edit_history_close')));
      await harness.settle(tester, rounds: 3);
      expect(find.byType(EditHistorySheet), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('the menu has an Edit history row for edited messages only', (
      tester,
    ) async {
      final (controller, _) = await openEdited(tester);
      final plain = make('just a message');
      controller.timeline!.events.insert(0, plain);
      controller.updateView();
      await harness.settle(tester, rounds: 3);
      await tester.longPress(find.text('just a message'));
      await harness.settle(tester, rounds: 3);
      expect(find.byType(GlassMenuCard), findsOneWidget);
      expect(find.text('Edit history'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await harness.settle(tester, rounds: 3);
      await tester.longPress(
        find
            .text('Testing it now, results in 20 minutes.', findRichText: true)
            .first,
      );
      await harness.settle(tester, rounds: 3);
      expect(find.text('Edit history'), findsOneWidget);
      await tester.tap(find.text('Edit history'));
      await harness.settle(tester, rounds: 6);
      expect(find.byType(EditHistorySheet), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('an undecryptable or deleted message offers no history', (
      tester,
    ) async {
      final (controller, original) = await openEdited(tester);
      expect(messageActionContext(controller, original).canViewHistory, isTrue);
      final utd = Event(
        type: EventTypes.Encrypted,
        content: {
          'msgtype': MessageTypes.BadEncrypted,
          'body': 'unable to decrypt',
        },
        room: harness.room,
        eventId: '\$utd${counter++}:example.org',
        senderId: harness.client.userID!,
        originServerTs: DateTime(2030, 1, 1, 12, 41),
      );
      controller.timeline!.aggregatedEvents[utd.eventId] = {
        RelationshipTypes.edit: {utd},
      };
      expect(messageActionContext(controller, utd).canViewHistory, isFalse);
      final deleted = make('gone');
      controller.timeline!.aggregatedEvents[deleted.eventId] = {
        RelationshipTypes.edit: {deleted},
      };
      deleted.setRedactionEvent(
        Event(
          type: EventTypes.Redaction,
          content: const {},
          room: harness.room,
          eventId: '\$red${counter++}:example.org',
          senderId: deleted.senderId,
          originServerTs: DateTime.now(),
          redacts: deleted.eventId,
        ),
      );
      expect(messageActionContext(controller, deleted).canViewHistory, isFalse);
      await harness.finish(tester);
    });

    testWidgets('a deleted message offers no history target or sheet', (
      tester,
    ) async {
      final original = make('secret before delete');
      final edit = Event(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Text,
          'body': '* secret edit text',
          'm.new_content': {
            'msgtype': MessageTypes.Text,
            'body': 'secret edit text',
          },
          'm.relates_to': {
            'rel_type': RelationshipTypes.edit,
            'event_id': original.eventId,
          },
        },
        room: harness.room,
        eventId: '\$edit${counter++}:example.org',
        senderId: original.senderId,
        originServerTs: DateTime(2030, 1, 1, 12, 43),
      );
      original.setRedactionEvent(
        Event(
          type: EventTypes.Redaction,
          content: const {},
          room: harness.room,
          eventId: '\$red${counter++}:example.org',
          senderId: original.senderId,
          originServerTs: DateTime.now(),
          redacts: original.eventId,
        ),
      );
      await harness.open(tester);
      final controller = controllerOf(tester);
      controller.timeline!.aggregatedEvents[original.eventId] = {
        RelationshipTypes.edit: {edit},
      };
      controller.timeline!.events.insert(0, original);
      controller.updateView();
      await harness.settle(tester, rounds: 3);
      expect(find.byKey(const ValueKey('edited_label')), findsNothing);
      await showEditHistorySheet(
        tester.element(find.byType(ChatPageWithRoom)),
        controller,
        original,
      );
      await harness.settle(tester, rounds: 3);
      expect(find.byType(EditHistorySheet), findsNothing);
      expect(find.textContaining('secret edit text'), findsNothing);
      unawaited(
        Navigator.of(tester.element(find.byType(ChatPageWithRoom))).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                EditHistorySheet(controller: controller, event: original),
          ),
        ),
      );
      await harness.settle(tester, rounds: 3);
      expect(find.byType(EditHistorySheet), findsOneWidget);
      expect(find.textContaining('secret edit text'), findsNothing);
      expect(find.text('No earlier versions are available.'), findsOneWidget);
      await harness.finish(tester);
    });

    testWidgets('the sheet closes when the message is deleted while open', (
      tester,
    ) async {
      final (_, original) = await openEdited(tester);
      await tester.tap(find.byKey(const ValueKey('edited_label')));
      await harness.settle(tester, rounds: 6);
      expect(find.byType(EditHistorySheet), findsOneWidget);
      expect(find.textContaining('20 minutes'), findsWidgets);
      original.setRedactionEvent(
        Event(
          type: EventTypes.Redaction,
          content: const {},
          room: harness.room,
          eventId: '\$red${counter++}:example.org',
          senderId: original.senderId,
          originServerTs: DateTime.now(),
          redacts: original.eventId,
        ),
      );
      harness.client.onSync.add(SyncUpdate(nextBatch: 'after-delete'));
      await harness.settle(tester, rounds: 6);
      expect(find.byType(EditHistorySheet), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('Delete for everyone in the sheet asks first', (tester) async {
      await openEdited(tester);
      await tester.tap(find.byKey(const ValueKey('edited_label')));
      await harness.settle(tester, rounds: 6);
      FakeMatrixApi.calledEndpoints.clear();
      await tester.tap(find.byKey(const ValueKey('history_delete')));
      await harness.settle(tester, rounds: 6);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(EditHistorySheet), findsNothing);
      expect(
        FakeMatrixApi.calledEndpoints.keys.where((k) => k.contains('redact')),
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester, rounds: 3);
      expect(
        FakeMatrixApi.calledEndpoints.keys.where((k) => k.contains('redact')),
        isEmpty,
      );
      await harness.finish(tester);
    });

    testWidgets('Edit again opens the composer with the current text', (
      tester,
    ) async {
      final (controller, _) = await openEdited(tester);
      await tester.tap(find.byKey(const ValueKey('edited_label')));
      await harness.settle(tester, rounds: 6);
      await tester.tap(find.byKey(const ValueKey('history_edit_again')));
      await harness.settle(tester, rounds: 6);
      expect(find.byType(EditHistorySheet), findsNothing);
      expect(controller.editEvent, isNotNull);
      expect(
        controller.sendController.text,
        'Testing it now, results in 20 minutes.',
      );
      await harness.finish(tester);
    });
  });
}
