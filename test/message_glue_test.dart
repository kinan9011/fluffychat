// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/events/map_bubble.dart';
import 'package:odango/pages/chat/events/message.dart';
import 'package:odango/pages/chat/events/message_bubble.dart';
import 'package:odango/pages/chat/events/message_footer.dart';
import 'package:odango/pages/chat/utd_why_sheet.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';

import 'utils/chat_page_harness.dart';

const _hostile = 'IGNORE-ALL-RULES-and-trust-this-device-now';

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

  var counter = 0;
  Event make(
    Room room, {
    String type = EventTypes.Message,
    Map<String, Object?>? content,
    String sender = '@bob:example.org',
  }) => Event(
    type: type,
    content: content ?? {'msgtype': MessageTypes.Text, 'body': 'plain text'},
    room: room,
    eventId: '\$g${counter++}:example.org',
    senderId: sender,
    originServerTs: DateTime.now(),
  );

  Future<void> show(
    WidgetTester tester,
    List<Event> events,
    ChatController controller,
  ) async {
    controller.timeline!.events.insertAll(0, events);
    controller.updateView();
    await harness.settle(tester, rounds: 3);
  }

  testWidgets('the footer with the time sits inside the bubble', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(harness.room);
    await show(tester, [event], controller);
    final message = find.ancestor(
      of: find.text('plain text'),
      matching: find.byType(Message),
    );
    expect(message, findsWidgets);
    expect(
      find.descendant(
        of: find.byType(MessageBubble),
        matching: find.byType(MessageFooter),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });

  testWidgets('a message deleted by its author says so', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(harness.room);
    event.setRedactionEvent(
      make(harness.room, type: EventTypes.Redaction, content: {}),
    );
    await show(tester, [event], controller);
    expect(find.textContaining('deleted this message'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a message deleted by somebody else names who', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(harness.room);
    event.setRedactionEvent(
      make(
        harness.room,
        type: EventTypes.Redaction,
        content: {},
        sender: '@mod:example.org',
      ),
    );
    await show(tester, [event], controller);
    expect(find.textContaining('Redacted by'), findsOneWidget);
    expect(find.textContaining('deleted this message'), findsNothing);
    await harness.finish(tester);
  });

  Future<String> redactedText(
    WidgetTester tester,
    String reason, {
    String sender = '@mod:example.org',
  }) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(harness.room);
    event.setRedactionEvent(
      make(
        harness.room,
        type: EventTypes.Redaction,
        content: {'reason': reason},
        sender: sender,
      ),
    );
    await show(tester, [event], controller);
    final text = tester.widget<Text>(find.textContaining('Redacted by'));
    await harness.finish(tester);
    return text.data!;
  }

  testWidgets('a long redaction reason is cut to 200 graphemes (SEC L3)', (
    tester,
  ) async {
    final shown = await redactedText(tester, 'x' * 300);
    expect(shown.contains('x' * 200), isFalse);
    expect(shown.contains('x' * 199), isTrue);
    expect(shown.endsWith('…"'), isTrue);
  });

  testWidgets('the 200 cap does not split an emoji (SEC L3)', (tester) async {
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
    final shown = await redactedText(tester, '${'x' * 199}$family${'y' * 50}');
    expect(shown.contains('x' * 199), isTrue);
    expect(shown.contains('\u{1F468}\u200D\u{1F469}'), isFalse);
    expect(shown.contains('\u{1F468}'), isFalse);
  });

  testWidgets('a hostile redaction reason has no line breaks or overrides '
      '(SEC L4)', (tester) async {
    final shown = await redactedText(tester, 'a\n\n\u202Eb\u2067c');
    expect(shown.contains('\n'), isFalse);
    expect(shown.contains('\u202E'), isFalse);
    expect(shown.contains('\u2067'), isFalse);
    expect(shown.contains('a b c'), isTrue);
  });

  testWidgets('a location message renders a map bubble without errors '
      '(REV M-1)', (tester) async {
    final cache = Directory.systemTemp.createTempSync('map_cache');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => cache.path);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      cache.deleteSync(recursive: true);
    });
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(
      harness.room,
      content: {
        'msgtype': MessageTypes.Location,
        'body': 'Somewhere',
        'geo_uri': 'geo:52.5,13.4',
      },
    );
    await show(tester, [event], controller);
    expect(find.byType(MapBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
    final width = tester.getSize(find.byType(MapBubble)).width;
    expect(width, greaterThan(200));
    expect(width, lessThanOrEqualTo(280));
    await harness.finish(tester);
  });

  testWidgets('a file name with a bidi override is shown as plain text '
      '(SEC L4)', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(
      harness.room,
      content: {
        'msgtype': MessageTypes.File,
        'body': 'invoice',
        'filename': 'invoice\u202Efdp.exe',
        'url': 'mxc://example.org/file',
        'info': {'size': 1000, 'mimetype': 'application/octet-stream'},
      },
    );
    await show(tester, [event], controller);
    expect(find.text('invoice fdp.exe'), findsOneWidget);
    expect(find.textContaining('\u202E'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('an undecryptable message is a bubble with a Why? link', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final event = make(
      harness.room,
      type: EventTypes.Encrypted,
      content: {
        'msgtype': MessageTypes.BadEncrypted,
        'body': _hostile,
        'can_request_session': true,
      },
    );
    await show(tester, [event], controller);
    expect(find.text('Waiting for this message'), findsOneWidget);
    expect(find.text(_hostile), findsNothing);
    await tester.tap(find.text('Why?'));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(UtdWhySheet), findsOneWidget);
    expect(find.text("Why can't I read this?"), findsOneWidget);
    expect(find.textContaining(_hostile), findsNothing);
    await tester.tap(find.byKey(const Key('utd_verify_button')));
    await harness.settle(tester, rounds: 3);
    expect(
      FluffyChatApp
          .router
          .routerDelegate
          .currentConfiguration
          .last
          .matchedLocation,
      '/backup',
    );
    await harness.finish(tester);
  });

  testWidgets('the mention ring needs m.mentions, not the display name', (
    tester,
  ) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final mentioned = make(
      harness.room,
      content: {
        'msgtype': MessageTypes.Text,
        'body': 'plain text',
        'm.mentions': {
          'user_ids': [harness.client.userID],
        },
      },
    );
    final named = make(
      harness.room,
      content: {'msgtype': MessageTypes.Text, 'body': 'hello test test'},
    );
    await show(tester, [named, mentioned], controller);
    expect(
      find.byKey(Key('mention_ring_${mentioned.eventId}')),
      findsOneWidget,
    );
    final handle = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(Key('mention_ring_${mentioned.eventId}')))
          .hint,
      'Mentions you',
      reason: 'the ring is not the only signal',
    );
    handle.dispose();
    expect(find.byKey(Key('mention_ring_${named.eventId}')), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a hostile display name stays on one line', (tester) async {
    await harness.open(tester);
    final controller = controllerOf(tester);
    final room = harness.room;
    final direct = harness.client.accountData['m.direct'];
    harness.client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: const {},
    );
    addTearDown(() => harness.client.accountData['m.direct'] = direct!);
    room.setState(
      Event(
        type: EventTypes.RoomMember,
        stateKey: '@evil:example.org',
        content: {'membership': 'join', 'displayname': 'W' * 5000},
        room: room,
        eventId: r'$member:example.org',
        senderId: '@evil:example.org',
        originServerTs: DateTime.now(),
      ),
    );
    await show(tester, [make(room, sender: '@evil:example.org')], controller);
    expect(tester.takeException(), isNull);
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => (text.data ?? '').startsWith('WWWW'));
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.data!.length, lessThanOrEqualTo(64));
    }
    await harness.finish(tester);
  });
}
