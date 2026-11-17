// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:fluffychat/pages/topics/sending_to_bar.dart';
import 'package:fluffychat/pages/topics/topic_chip_bar.dart';
import 'package:fluffychat/pages/topics/topic_create_sheet.dart';
import 'package:fluffychat/pages/topics/topic_row.dart';
import 'package:fluffychat/utils/topics/topic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

Topic topic(
  String id,
  String title, {
  String icon = 'tag',
  int unread = 0,
  bool mention = false,
  String preview = 'last message',
}) => Topic(
  rootEventId: id,
  title: title,
  icon: icon,
  replyCount: 3,
  lastActivity: DateTime(2026, 11, 17, 12, 40),
  hue: TopicParser.hueFor(id),
  lastSender: 'Priya',
  lastPreview: preview,
  unread: unread,
  mention: mention,
);

final sample = [
  topic(r'$a:x', 'Releases', icon: 'rocket_launch', unread: 4, mention: true),
  topic(r'$b:x', 'Design', icon: 'palette'),
  topic(r'$c:x', 'Bugs', icon: 'bug_report', unread: 120),
  topic(r'$d:x', '', preview: ''),
];

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      pumpGoldenWidget(tester, child, size: const Size(400, 400));

  group('TopicRow', () {
    testWidgets('title, preview, time and badges', (tester) async {
      var taps = 0;
      await pump(
        tester,
        Column(
          children: [
            for (final t in sample) TopicRow(topic: t, onTap: () => taps++),
          ],
        ),
      );
      expect(find.text('Releases'), findsOneWidget);
      expect(find.text('Priya: last message'), findsNWidgets(3));
      expect(find.text('4'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.byIcon(Icons.alternate_email_rounded), findsOneWidget);
      expect(find.text('Untitled topic'), findsOneWidget);
      await tester.tap(find.text('Releases'));
      expect(taps, 1);
    });

    testWidgets('a row is at least 72 px high and one button for readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, TopicRow(topic: sample.first, onTap: () {}));
      expect(
        tester.getSize(find.byType(TopicRow)).height,
        greaterThanOrEqualTo(72),
      );
      expect(
        find.bySemanticsLabel('Releases, 4 unread, Priya: last message'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('an icon the sender made up falls back to the tag', (
      tester,
    ) async {
      await pump(
        tester,
        TopicRow(
          topic: topic(r'$z:x', 'Odd', icon: 'rm -rf'),
          onTap: () {},
        ),
      );
      expect(find.byIcon(Icons.tag_rounded), findsOneWidget);
    });
  });

  group('TopicChipBar', () {
    Widget bar({String? active, List<Topic>? topics}) => TopicChipBar(
      topics: topics ?? sample,
      activeThreadId: active,
      onGeneral: () {},
      onTopic: (_) {},
      onAll: () {},
    );

    bool selected(WidgetTester tester, String key) =>
        tester
            .getSemantics(find.byKey(ValueKey(key)))
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;

    testWidgets('General is selected without a topic, a topic when open', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, bar());
      expect(selected(tester, 'topic_chip_general'), isTrue);
      expect(selected(tester, r'topic_chip_$a:x'), isFalse);
      await pump(tester, bar(active: r'$a:x'));
      expect(selected(tester, 'topic_chip_general'), isFalse);
      expect(selected(tester, r'topic_chip_$a:x'), isTrue);
      semantics.dispose();
    });

    testWidgets('the unread count is part of the label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, bar());
      expect(find.bySemanticsLabel('Releases, 4'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a large text size does not break the bar', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, bar());
      expect(tester.takeException(), isNull);
      expect(find.text('Releases'), findsOneWidget);
    });

    testWidgets('a long title is cut, not overflowing', (tester) async {
      await pump(tester, bar(topics: [topic(r'$q:x', 'Very ' * 40)]));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('SendingToBar names the topic or says untitled', (tester) async {
    await pump(tester, const SendingToBar(title: 'Releases'));
    expect(find.text('Sending to # Releases'), findsOneWidget);
    await pump(tester, const SendingToBar(title: ''));
    expect(find.text('Sending to # Untitled topic'), findsOneWidget);
  });

  group('TopicCreateSheet', () {
    late Client client;
    late Room room;

    setUpAll(() async {
      client = await prepareTestClient();
      room = client.rooms.firstWhere((r) => r.membership == Membership.join);
    });
    tearDownAll(() => client.dispose(closeDatabase: true));

    testWidgets('twelve icons, one selected, a title is needed', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        TopicCreateSheet(room: room),
        size: const Size(400, 700),
      );
      expect(find.byKey(const ValueKey(r'topic_icon_tag')), findsOneWidget);
      expect(TopicIcons.allowed, hasLength(12));
      final c = tester.state<TopicCreateController>(
        find.byType(TopicCreateSheet),
      );
      expect(c.canCreate, isFalse);
      c.title.text = '   ';
      c.changed();
      expect(c.canCreate, isFalse);
      c.title.text = 'Releases';
      c.selectIcon('forum');
      c.changed();
      await tester.pump();
      expect(c.canCreate, isTrue);
      expect(c.icon, 'forum');
    });
  });

  group('goldens', () {
    testGoldens('topic rows', (tester) async {
      await expectGoldenVariants(
        tester,
        'topic_rows',
        Column(
          children: [for (final t in sample) TopicRow(topic: t, onTap: () {})],
        ),
        size: const Size(400, 330),
      );
    });

    testGoldens('chip bar', (tester) async {
      await expectGoldenVariants(
        tester,
        'topic_chip_bar',
        Column(
          children: [
            TopicChipBar(
              topics: sample,
              activeThreadId: r'$a:x',
              onGeneral: () {},
              onTopic: (_) {},
              onAll: () {},
            ),
          ],
        ),
        size: const Size(400, 90),
      );
    });

    testGoldens('sending to bar', (tester) async {
      await expectGoldenVariants(
        tester,
        'sending_to_bar',
        const Align(
          alignment: Alignment.bottomCenter,
          child: SendingToBar(title: 'Releases'),
        ),
        size: const Size(400, 60),
      );
    });

    testGoldens('create sheet', (tester) async {
      final client = (await tester.runAsync(prepareTestClient))!;
      final room = client.rooms.firstWhere(
        (r) => r.membership == Membership.join,
      );
      for (final variant in goldenVariants) {
        await pumpGoldenWidget(
          tester,
          TopicCreateSheet(key: ValueKey(variant.suffix), room: room),
          brightness: variant.brightness,
          rtl: variant.rtl,
          locale: variant.locale,
          size: const Size(400, 560),
        );
        final c = tester.state<TopicCreateController>(
          find.byType(TopicCreateSheet),
        );
        c.title.text = 'Releases';
        c.selectIcon('rocket_launch');
        c.changed();
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/topic_create_sheet_${variant.suffix}.png'),
        );
      }
      await tester.runAsync(() => client.dispose(closeDatabase: true));
    });
  });

  test('creating a topic asks to trust unverified people first', () {
    final source = File(
      'lib/pages/topics/topic_create_sheet.dart',
    ).readAsStringSync();
    expect(source, contains('await showTrustUserInRoomDialog(context'));
  });
}
