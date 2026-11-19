// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/poll_composer/poll_composer.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> openComposer(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
  }) async {
    await harness.open(tester, width: width, height: height);
    unawaited(
      showPollComposer(
        tester.element(find.byType(ChatPageWithRoom)),
        harness.client.getRoomById('!calls:example.com')!,
      ),
    );
    await harness.settle(tester, rounds: 3);
    api.clear();
  }

  PollComposerController composer(WidgetTester tester) =>
      tester.state<PollComposerController>(find.byType(PollComposer));

  bool createEnabled(WidgetTester tester) =>
      tester.widget<InkWell>(find.byKey(const ValueKey('poll_create'))).onTap !=
      null;

  Future<void> fill(
    WidgetTester tester, {
    String question = 'Which protocol?',
    List<String> answers = const ['Matrix', 'XMPP'],
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('poll_question_field')),
      question,
    );
    for (var i = 0; i < answers.length; i++) {
      final field = find.byKey(ValueKey('poll_answer_$i'));
      if (field.evaluate().isEmpty) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('poll_add_answer')),
        );
        await tester.tap(find.byKey(const ValueKey('poll_add_answer')));
        await tester.pump();
      }
      await tester.ensureVisible(field);
      await tester.enterText(field, answers[i]);
    }
    await tester.pump();
  }

  List<RecordedRequest> sent() =>
      api.requests('/send/org.matrix.msc3381.poll.start/', method: 'PUT');

  Future<void> waitForSend(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      if (sent().isNotEmpty && find.byType(PollComposer).evaluate().isEmpty) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, Object?> body() => sent().single.json! as Map<String, Object?>;

  testWidgets('Create is disabled until the poll is valid', (tester) async {
    await openComposer(tester);
    expect(createEnabled(tester), isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('poll_question_field')),
      'Q',
    );
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const ValueKey('poll_answer_0')), 'A');
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const ValueKey('poll_answer_1')), 'B');
    await tester.pump();
    expect(createEnabled(tester), isTrue);
    await tester.enterText(find.byKey(const ValueKey('poll_answer_1')), 'a');
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    expect(find.byKey(const ValueKey('poll_error')), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('up to ten answers, remove only above two', (tester) async {
    await openComposer(tester);
    expect(find.byKey(const ValueKey('poll_remove_0')), findsNothing);
    final c = composer(tester);
    for (var i = 0; i < 8; i++) {
      expect(c.canAddAnswer, isTrue);
      c.addAnswer();
      await tester.pump();
    }
    expect(c.answers, hasLength(10));
    expect(c.canAddAnswer, isFalse);
    expect(find.byKey(const ValueKey('poll_add_answer')), findsNothing);
    c.addAnswer();
    await tester.pump();
    expect(c.answers, hasLength(10));
    expect(find.byKey(const ValueKey('poll_remove_0')), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      c.removeAnswer(c.answers.last);
      await tester.pump();
    }
    expect(c.answers, hasLength(2));
    c.removeAnswer(c.answers.last);
    expect(c.answers, hasLength(2));
    await harness.finish(tester);
  });

  testWidgets('quiz and multiple answers switch each other off', (
    tester,
  ) async {
    await openComposer(tester);
    final c = composer(tester);
    c.toggleMultiple(true);
    await tester.pump();
    expect(c.multiple, isTrue);
    c.toggleQuiz(true);
    await tester.pump();
    expect([c.quiz, c.multiple], [true, false]);
    c.toggleMultiple(true);
    await tester.pump();
    expect([c.quiz, c.multiple], [false, true]);
    await harness.finish(tester);
  });

  testWidgets('a quiz needs one correct answer; tapping again unmarks it', (
    tester,
  ) async {
    await openComposer(tester);
    await fill(tester);
    composer(tester).toggleQuiz(true);
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    expect(find.text('Mark the correct answer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poll_correct_1')));
    await tester.pump();
    expect(createEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('poll_correct_0')));
    await tester.pump();
    expect(composer(tester).answers.map((a) => a.correct), [true, false]);
    await tester.tap(find.byKey(const ValueKey('poll_correct_0')));
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    await harness.finish(tester);
  });

  testWidgets('Create sends one poll with the expected content', (
    tester,
  ) async {
    await openComposer(tester);
    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('poll_hide_results')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    await waitForSend(tester);
    expect(sent(), hasLength(1));
    final sentBody = body();
    final start = sentBody['org.matrix.msc3381.poll.start']! as Map;
    expect(start['kind'], 'org.matrix.msc3381.poll.undisclosed');
    expect(start['max_selections'], 1);
    expect((start['answers']! as List).map((a) => (a as Map)['id']), [
      '1',
      '2',
    ]);
    expect(sentBody.containsKey('com.swovo.odango.poll.quiz'), isFalse);
    expect(find.byType(PollComposer), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a quiz carries the correct answer', (tester) async {
    await openComposer(tester);
    await fill(tester);
    composer(tester).toggleQuiz(true);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll_correct_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    await waitForSend(tester);
    final sentBody = body();
    expect(sentBody['com.swovo.odango.poll.quiz'], {
      'correct_answer_ids': ['2'],
    });
    await harness.finish(tester);
  });

  testWidgets('reordering changes the order that is sent', (tester) async {
    await openComposer(tester);
    await fill(tester, answers: ['one', 'two', 'three']);
    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded).first,
      const Offset(0, 120),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final order = composer(tester).answers.map((a) => a.text.text).toList();
    expect(order, isNot(['one', 'two', 'three']));
    expect(order, unorderedEquals(['one', 'two', 'three']));
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    await waitForSend(tester);
    final start = body()['org.matrix.msc3381.poll.start']! as Map;
    final texts = [
      for (final a in start['answers']! as List)
        (a as Map)['org.matrix.msc1767.text'],
    ];
    expect(texts, order);
    await harness.finish(tester);
  });

  testWidgets('a second tap while sending does not send twice', (tester) async {
    await openComposer(tester);
    await fill(tester);
    final create = find.byKey(const ValueKey('poll_create'));
    await tester.tap(create);
    await tester.tap(create, warnIfMissed: false);
    await waitForSend(tester);
    expect(sent(), hasLength(1));
    await harness.finish(tester);
  });

  testWidgets('the honest notes are shown', (tester) async {
    await openComposer(tester);
    expect(find.text('Votes are visible to room members.'), findsOneWidget);
    composer(tester).toggleQuiz(true);
    await tester.pump();
    expect(
      find.textContaining('Other apps show a quiz as a normal poll'),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets('on a small screen with the keyboard open Create stays visible', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await openComposer(tester, width: 320, height: 480);
    await fill(tester);
    final create = find.byKey(const ValueKey('poll_create'));
    final rect = tester.getRect(create);
    expect(rect.bottom, lessThanOrEqualTo(480 - 200 + 1));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await tester.tap(create);
    await waitForSend(tester);
    expect(sent(), hasLength(1));
    await harness.finish(tester);
  });

  testWidgets('a retry after a failed send reuses the transaction id', (
    tester,
  ) async {
    await openComposer(tester);
    await fill(tester);
    api.failNextSend = true;
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    for (
      var i = 0;
      i < 50 && api.log.where((r) => r.method == 'PUT').isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await harness.settle(tester, rounds: 3);
    expect(find.byType(PollComposer), findsOneWidget);
    expect(createEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    await waitForSend(tester);
    final puts = api.requests('/send/', method: 'PUT');
    expect(puts, hasLength(2));
    String txid(RecordedRequest r) => r.path.split('/').last;
    expect(txid(puts.first), txid(puts.last));
    await harness.finish(tester);
  });

  testWidgets('an edit after a failed send gets a new transaction id', (
    tester,
  ) async {
    await openComposer(tester);
    await fill(tester);
    api.failNextSend = true;
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    for (
      var i = 0;
      i < 50 && api.log.where((r) => r.method == 'PUT').isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await harness.settle(tester, rounds: 3);
    await tester.enterText(
      find.byKey(const ValueKey('poll_question_field')),
      'Which protocol, really?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll_create')));
    await waitForSend(tester);
    final puts = api.requests('/send/', method: 'PUT');
    expect(puts, hasLength(2));
    String txid(RecordedRequest r) => r.path.split('/').last;
    expect(txid(puts.first), isNot(txid(puts.last)));
    await harness.finish(tester);
  });

  test('the sheet asks to trust unverified people before it sends', () {
    final source = File(
      'lib/pages/chat/poll_composer/poll_composer.dart',
    ).readAsStringSync();
    expect(source, contains('await showTrustUserInRoomDialog(context'));
  });
}
