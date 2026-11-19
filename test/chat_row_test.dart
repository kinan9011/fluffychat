// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/pages/chat_list/chat_list_item.dart';
import 'package:odango/utils/chat_list/chat_row_model.dart';
import 'package:odango/utils/draft_store.dart';
import 'package:odango/widgets/avatar.dart';

import 'utils/chat_row_fixtures.dart';
import 'utils/golden.dart';
import 'utils/test_client.dart';

class _MemoryDatabase implements DatabaseApi {
  final _objects = <String, Map<String, Object?>>{};

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async => _objects[cacheKey] = object;

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async {
    final content = _objects[cacheKey];
    return content == null ? null : (content: content, savedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  setUp(
    () => client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@anna:example.org': ['!anna:example.org'],
      },
    ),
  );

  tearDown(() => client.accountData.remove('m.direct'));

  DateTime today(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  Room anna({
    int unread = 0,
    int highlight = 0,
    Map<String, double?> tags = const {},
    String name = 'Anna',
  }) => testChat(
    client,
    '!anna:example.org',
    name: name,
    unread: unread,
    highlight: highlight,
    lastBody: 'Hi',
    lastTime: today(12, 40),
    tags: tags,
  );

  Widget row(Room room, {bool active = false, DraftStore? drafts}) =>
      ChatListItem(room, activeChat: active, drafts: drafts, onTap: () {});

  Future<void> pumpRow(
    WidgetTester tester,
    Room room, {
    bool rtl = false,
    double textScale = 1,
    bool active = false,
    DraftStore? drafts,
  }) => pumpGoldenWidget(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Align(
          alignment: Alignment.topCenter,
          child: row(room, active: active, drafts: drafts),
        ),
      ),
    ),
    rtl: rtl,
    locale: rtl ? const Locale('ar') : const Locale('en'),
    size: const Size(400, 600),
  ).then((_) => tester.pump(const Duration(seconds: 35)));

  Future<DraftStore> draftStore(Map<String, Object> values) async {
    final database = _MemoryDatabase();
    final store = DraftStore.forTesting(() => database);
    for (final entry in values.entries) {
      await store.write(entry.key.substring('draft_'.length), '${entry.value}');
    }
    return store;
  }

  String rowLabel(WidgetTester tester) => tester
      .getSemantics(
        find.descendant(
          of: find.byType(ChatListItem),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label != null,
          ),
        ),
      )
      .label;

  String labelStarting(WidgetTester tester, String start) =>
      find.semantics.byLabel(RegExp('^$start')).evaluate().single.label;

  Future<SemanticsHandle> semanticsOn(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await tester.pump();
    return handle;
  }

  testWidgets('a row is at least 76 high and its avatar is 56', (tester) async {
    await pumpRow(tester, anna());
    expect(tester.getSize(find.byType(ChatListItem)).height, 76);
    expect(tester.getSize(find.byType(Avatar)), const Size(56, 56));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text grows the row, the name takes two lines', (
    tester,
  ) async {
    await pumpRow(
      tester,
      anna(name: 'A very long chat name that cannot fit one line at all'),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ChatListItem)).height, greaterThan(76));
    final name = tester.widget<Text>(
      find.text('A very long chat name that cannot fit one line at all'),
    );
    expect(name.maxLines, 2);
  });

  void muteRoom(String id) {
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            {
              'rule_id': id,
              'default': false,
              'enabled': true,
              'conditions': <Object?>[],
              'actions': <Object?>[],
            },
          ],
        },
      },
    );
    addTearDown(() => client.accountData.remove('m.push_rules'));
  }

  testWidgets('a muted chat shows the muted icon and the muted badge colour', (
    tester,
  ) async {
    muteRoom('!anna:example.org');
    await pumpRow(tester, anna(unread: 3));
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    final badge = tester.widget<Container>(
      find.ancestor(of: find.text('3'), matching: find.byType(Container)).first,
    );
    final tokens = AppTokens.of(tester.element(find.byType(ChatListItem)));
    expect((badge.decoration! as BoxDecoration).color, tokens.mbad);
  });

  testWidgets('an unmuted unread chat uses the accent badge', (tester) async {
    await pumpRow(tester, anna(unread: 3));
    final badge = tester.widget<Container>(
      find.ancestor(of: find.text('3'), matching: find.byType(Container)).first,
    );
    final tokens = AppTokens.of(tester.element(find.byType(ChatListItem)));
    expect((badge.decoration! as BoxDecoration).color, tokens.acc);
    expect(find.byIcon(Icons.volume_off_rounded), findsNothing);
  });

  testWidgets('a thread reply as last message shows the thread chip', (
    tester,
  ) async {
    final room = anna();
    await pumpRow(tester, room);
    expect(find.text('Thread'), findsNothing);
    final last = room.lastEvent!;
    room.lastEvent = Event(
      type: last.type,
      content: {
        ...last.content,
        'm.relates_to': {'rel_type': 'm.thread', 'event_id': '\$root'},
      },
      room: room,
      eventId: last.eventId,
      senderId: last.senderId,
      originServerTs: last.originServerTs,
    );
    await pumpRow(tester, room);
    expect(find.text('Thread'), findsOneWidget);
  });

  testWidgets('a mention shows the @ badge', (tester) async {
    await pumpRow(tester, anna(unread: 2, highlight: 1));
    expect(find.byIcon(Icons.alternate_email_rounded), findsOneWidget);
    await pumpRow(tester, anna(unread: 2));
    expect(find.byIcon(Icons.alternate_email_rounded), findsNothing);
  });

  testWidgets('a pinned chat without unread shows the rotated pin', (
    tester,
  ) async {
    await pumpRow(tester, anna(tags: {'m.favourite': 0.5}));
    final pin = find.byIcon(Icons.push_pin_rounded);
    expect(pin, findsOneWidget);
    expect(
      tester
          .widget<Transform>(
            find.ancestor(of: pin, matching: find.byType(Transform)).first,
          )
          .transform
          .getRotation()
          .entry(0, 1),
      isNot(0),
    );
    await pumpRow(tester, anna(unread: 1, tags: {'m.favourite': 0.5}));
    expect(find.byIcon(Icons.push_pin_rounded), findsNothing);
  });

  testWidgets('semantics describe the whole row in one label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, anna(unread: 3, tags: {'m.favourite': 0.5}));
    expect(
      rowLabel(tester),
      'Anna, 3 unread, last message Hi, 12:40 PM, Pinned',
    );
    handle.dispose();
  });

  testWidgets('a read chat has no unread count in its label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, anna());
    final label = rowLabel(tester);
    expect(label, startsWith('Anna, last message Hi, 12:40'));
    expect(label, isNot(contains('unread')));
    handle.dispose();
  });

  testWidgets('a chat marked unread or an invite says so in its label', (
    tester,
  ) async {
    final handle = await semanticsOn(tester);
    final marked = anna();
    marked.roomAccountData['m.marked_unread'] = BasicEvent(
      type: 'm.marked_unread',
      content: {'unread': true},
    );
    await pumpRow(tester, marked);
    expect(
      labelStarting(tester, 'Anna'),
      'Anna, last message Hi, 12:40 PM, Unread',
    );
    final invite = testChat(
      client,
      '!inv:example.org',
      name: 'Invited',
      membership: Membership.invite,
    );
    await pumpRow(tester, invite);
    expect(labelStarting(tester, 'Invited'), contains('Unread'));
    await pumpRow(tester, anna(unread: 3));
    expect(labelStarting(tester, 'Anna'), isNot(contains(', Unread')));
    handle.dispose();
  });

  testWidgets('semantics announce the draft', (tester) async {
    final handle = await semanticsOn(tester);
    final drafts = await draftStore({'draft_!anna:example.org': 'hello'});
    await pumpRow(tester, anna(unread: 3), drafts: drafts);
    expect(rowLabel(tester), contains('last message Draft: hello'));
    handle.dispose();
  });

  testWidgets('the forget button stays reachable for screen readers', (
    tester,
  ) async {
    final handle = await semanticsOn(tester);
    var forgotten = 0;
    final room = testChat(
      client,
      '!left:example.org',
      name: 'Left chat',
      membership: Membership.leave,
      lastBody: 'Bye',
    );
    await pumpGoldenWidget(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: ChatListItem(room, onTap: () {}, onForget: () => forgotten++),
      ),
      size: const Size(400, 400),
    );
    await tester.pump(const Duration(seconds: 35));
    final node = find.semantics.byLabel(RegExp('^Left chat')).evaluate().single;
    final ids = node.getSemanticsData().customSemanticsActionIds!;
    final delete = ids.firstWhere(
      (id) => CustomSemanticsAction.getAction(id)!.label == 'Delete',
    );
    expect(find.byTooltip('Delete'), findsOneWidget);
    tester.semantics.performAction(
      find.semantics.byLabel(RegExp('^Left chat')),
      SemanticsAction.customAction,
      args: delete,
    );
    expect(forgotten, 1);
    handle.dispose();
  });

  testWidgets('RTL puts the avatar at the right edge', (tester) async {
    await pumpRow(tester, anna());
    final ltr = tester.getTopLeft(find.byType(Avatar)).dx;
    await pumpRow(tester, anna(), rtl: true);
    final rtl = tester.getTopRight(find.byType(Avatar)).dx;
    expect(ltr, 16);
    expect(rtl, 400 - 16);
  });

  test('tickFor', () {
    final own = client.userID!;
    Event event({
      String? sender,
      EventStatus status = EventStatus.synced,
      Room? room,
    }) => Event(
      type: EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'x'},
      room: room ?? Room(id: '!r:x', client: client),
      eventId: '\$e',
      senderId: sender ?? own,
      originServerTs: DateTime(2030),
      status: status,
    );
    expect(tickFor(null, own), RowTick.none);
    expect(tickFor(event(), null), RowTick.none);
    expect(tickFor(event(sender: '@other:x'), own), RowTick.none);
    expect(tickFor(event(), own), RowTick.sent);
    expect(tickFor(event(status: EventStatus.sending), own), RowTick.sending);
    expect(tickFor(event(status: EventStatus.sent), own), RowTick.sending);
    expect(tickFor(event(status: EventStatus.error), own), RowTick.error);
    final room = Room(id: '!r:x', client: client);
    room.receiptState.global.otherUsers['@bob:x'] = LatestReceiptStateData(
      '\$e',
      1,
    );
    expect(tickFor(event(room: room), own), RowTick.read);
    final ownOnly = Room(id: '!r:x', client: client);
    ownOnly.receiptState.global.latestOwnReceipt = LatestReceiptStateData(
      '\$e',
      1,
    );
    expect(tickFor(event(room: ownOnly), own), RowTick.sent);
  });

  testWidgets('the muted icon sits right after the name, not at the far end', (
    tester,
  ) async {
    muteRoom('!anna:example.org');
    await pumpRow(tester, anna());
    final name = tester.getTopRight(find.text('Anna'));
    final icon = tester.getTopLeft(find.byIcon(Icons.volume_off_rounded));
    expect(icon.dx - name.dx, 4);
    await pumpRow(tester, anna(), rtl: true);
    final rtlName = tester.getTopLeft(find.text('Anna'));
    final rtlIcon = tester.getTopRight(find.byIcon(Icons.volume_off_rounded));
    expect(rtlName.dx - rtlIcon.dx, 4);
  });

  testWidgets('the presence dot is 15 with a 2.5 ring in the row', (
    tester,
  ) async {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@pia:example.org': ['!pia:example.org'],
      },
    );
    await tester.runAsync(
      () => client.database.storePresence(
        '@pia:example.org',
        CachedPresence(PresenceType.online, 0, null, true, '@pia:example.org'),
      ),
    );
    await pumpRow(
      tester,
      testChat(
        client,
        '!pia:example.org',
        name: 'Pia',
        lastBody: 'Hi',
        lastTime: today(12, 40),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    final sizes = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(Avatar),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.constraints?.maxWidth)
        .whereType<double>()
        .toSet();
    expect(sizes, containsAll([15.0, 10.0]));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 35));
  });

  testWidgets('a very long muted name still leaves room for the icon', (
    tester,
  ) async {
    muteRoom('!anna:example.org');
    await pumpRow(tester, anna(name: 'Long ' * 30));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });

  testWidgets('the space mini avatar mirrors in RTL', (tester) async {
    final space = testChat(client, '!space:example.org', name: 'Space');
    Widget withSpace() => Align(
      alignment: Alignment.topCenter,
      child: ChatListItem(anna(), space: space, onTap: () {}),
    );
    double miniMinusMain() {
      final avatars = tester.widgetList<Avatar>(find.byType(Avatar)).toList();
      final mini = avatars.firstWhere((a) => a.size == 42);
      final main = avatars.firstWhere((a) => a.size == 42 && a != mini);
      return tester.getCenter(find.byWidget(mini)).dx -
          tester.getCenter(find.byWidget(main)).dx;
    }

    await pumpGoldenWidget(tester, withSpace(), size: const Size(400, 600));
    await tester.pump(const Duration(seconds: 35));
    expect(miniMinusMain(), lessThan(0));
    await pumpGoldenWidget(
      tester,
      withSpace(),
      rtl: true,
      locale: const Locale('ar'),
      size: const Size(400, 600),
    );
    await tester.pump(const Duration(seconds: 35));
    expect(miniMinusMain(), greaterThan(0));
  });

  test('tickFor shows the tick only for own messages, not state events', () {
    final own = client.userID!;
    Event event(String type) => Event(
      type: type,
      content: {'msgtype': 'm.text', 'body': 'x'},
      room: Room(id: '!r:x', client: client),
      eventId: '\$e',
      senderId: own,
      originServerTs: DateTime(2030),
    );
    expect(tickFor(event(EventTypes.RoomCreate), own), RowTick.none);
    expect(tickFor(event(EventTypes.RoomMember), own), RowTick.none);
    expect(tickFor(event(EventTypes.Message), own), RowTick.sent);
    expect(tickFor(event(EventTypes.Encrypted), own), RowTick.sent);
    expect(tickFor(event(EventTypes.Sticker), own), RowTick.sent);
  });

  Color? runColor(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith(text),
      ),
    );
    Color? color;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text?.startsWith(text) == true) {
        color = span.style?.color;
      }
      return true;
    });
    return color;
  }

  testWidgets(
    'a last message the retention timer hides is not in the preview (W13 audit C-11)',
    (tester) async {
      final room = anna();
      room.setState(
        Event(
          type: 'm.room.retention',
          stateKey: '',
          content: {'max_lifetime': 86400000, 'expire_on_clients': true},
          room: room,
          eventId: r'$retention',
          senderId: '@admin:example.org',
          originServerTs: DateTime(2020),
        ),
      );
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'old secret'},
        room: room,
        eventId: r'$old',
        senderId: '@anna:example.org',
        originServerTs: DateTime.now().subtract(const Duration(days: 3)),
      );
      await pumpRow(tester, room);
      expect(find.textContaining('old secret'), findsNothing);
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'new one'},
        room: room,
        eventId: r'$new',
        senderId: '@anna:example.org',
        originServerTs: DateTime.now(),
      );
      await pumpRow(tester, room);
      expect(find.textContaining('new one'), findsOneWidget);
    },
  );

  group('draft (W03-3)', () {
    const draftKey = 'draft_!anna:example.org';

    testWidgets('a draft shows Draft: in red, then the text', (tester) async {
      final drafts = await draftStore({draftKey: 'see you  at\n8'});
      await pumpRow(tester, anna(), drafts: drafts);
      final tokens = AppTokens.of(tester.element(find.byType(ChatListItem)));
      expect(find.textContaining('Draft: see you at 8'), findsOneWidget);
      expect(runColor(tester, 'Draft: '), tokens.red);
      expect(find.textContaining('Hi'), findsNothing);
    });

    testWidgets('the active row hides its draft (it is in the composer)', (
      tester,
    ) async {
      final drafts = await draftStore({draftKey: 'x'});
      await pumpRow(tester, anna(), drafts: drafts, active: true);
      expect(find.textContaining('Draft:'), findsNothing);
      expect(find.textContaining('Hi'), findsOneWidget);
    });

    testWidgets('on hover the prefix switches to the text colour', (
      tester,
    ) async {
      final drafts = await draftStore({draftKey: 'x'});
      await pumpRow(tester, anna(), drafts: drafts);
      final tokens = AppTokens.of(tester.element(find.byType(ChatListItem)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(ChatListItem)));
      await tester.pump();
      expect(runColor(tester, 'Draft: '), tokens.fg);
      await mouse.moveTo(const Offset(399, 599));
      await tester.pump();
      expect(runColor(tester, 'Draft: '), tokens.red);
    });

    testWidgets('a blank draft and no draft show the last message', (
      tester,
    ) async {
      final drafts = await draftStore({draftKey: '  \n '});
      await pumpRow(tester, anna(), drafts: drafts);
      expect(find.textContaining('Draft:'), findsNothing);
      expect(find.textContaining('Hi'), findsOneWidget);
    });

    testWidgets('typing beats the draft', (tester) async {
      final drafts = await draftStore({draftKey: 'x'});
      final room = anna();
      room.ephemerals['m.typing'] = BasicEvent(
        type: 'm.typing',
        content: {
          'user_ids': ['@anna:example.org'],
        },
      );
      await pumpRow(tester, room, drafts: drafts);
      expect(find.textContaining('Draft:'), findsNothing);
    });

    testWidgets('a long draft is cut to 120 characters', (tester) async {
      final drafts = await draftStore({draftKey: 'a' * 300});
      await pumpRow(tester, anna(), drafts: drafts);
      expect(find.textContaining('Draft: ${'a' * 120}'), findsOneWidget);
      expect(find.textContaining('a' * 121), findsNothing);
    });

    testWidgets('a change of the draft updates the row without a sync', (
      tester,
    ) async {
      final drafts = await draftStore({});
      await pumpRow(tester, anna(), drafts: drafts);
      expect(find.textContaining('Draft:'), findsNothing);
      await drafts.write('!anna:example.org', 'later');
      await tester.pump();
      expect(find.textContaining('Draft: later'), findsOneWidget);
      await drafts.remove('!anna:example.org');
      await tester.pump();
      expect(find.textContaining('Draft:'), findsNothing);
    });

    testWidgets('RTL keeps the draft readable', (tester) async {
      final drafts = await draftStore({draftKey: 'مرحبا'});
      await pumpRow(tester, anna(), drafts: drafts);
      await pumpRow(tester, anna(), drafts: drafts, rtl: true);
      expect(find.textContaining('مرحبا'), findsOneWidget);
    });
  });

  testWidgets('goldens: normal, unread, muted, mention, pinned, active', (
    tester,
  ) async {
    Room named(
      String name, {
      int unread = 0,
      int highlight = 0,
      Map<String, double?> tags = const {},
    }) => testChat(
      client,
      '!$name:example.org',
      name: name,
      unread: unread,
      highlight: highlight,
      lastBody: 'See you at the meeting tomorrow',
      lastTime: DateTime(2030, 1, 1),
      tags: tags,
    );
    final rooms = [
      named('Anna'),
      named('Ben', unread: 3),
      named('Cleo', unread: 1, highlight: 1),
      named('Dan', tags: {'m.favourite': 0.5}),
      named('Eve', unread: 120),
      named('Finn'),
      named('Gus', unread: 2),
      named('Hal'),
    ];
    muteRoom('!Gus:example.org');
    final drafts = await draftStore({'draft_!Hal:example.org': 'On my way'});
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final room in rooms)
          ChatListItem(
            room,
            activeChat: room.id.contains('Finn'),
            drafts: drafts,
            onTap: () {},
          ),
      ],
    );
    addTearDown(() => tester.pump(const Duration(seconds: 35)));
    await expectGoldenVariants(
      tester,
      'chat_row',
      Align(alignment: Alignment.topCenter, child: column),
      size: const Size(400, 700),
    );
  });
}
