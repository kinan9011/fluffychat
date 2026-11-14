// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show Tristate;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_tabs.dart';
import 'package:fluffychat/utils/chat_list/folder_filter.dart';
import 'package:fluffychat/utils/chat_list/folder_ref.dart';
import 'package:fluffychat/utils/chat_list/space_tabs_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

const _spaceA = SpaceTab(
  spaceId: '!a:x',
  name: 'Alpha',
  avatar: null,
  unread: 0,
);
const _spaceB = SpaceTab(
  spaceId: '!b:x',
  name: 'Beta',
  avatar: null,
  unread: 0,
);

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  Future<List<ChatListTabData>> tabData(
    WidgetTester tester, {
    List<SpaceTab> spaces = const [_spaceA, _spaceB],
    bool showFolders = true,
    SpaceNavigationMode mode = SpaceNavigationMode.tabs,
    bool showCounts = true,
    int Function(ChatListScope)? countOf,
  }) async {
    late List<ChatListTabData> result;
    await pumpGoldenWidget(
      tester,
      Builder(
        builder: (context) {
          result = chatListTabData(
            FolderFilter.tabs(
              mode: mode,
              spaces: spaces,
              tags: const [],
              showFoldersAfterSpaces: showFolders,
            ),
            l10n: L10n.of(context),
            mode: mode,
            showCounts: showCounts,
            countOf: countOf ?? (_) => 0,
          );
          return const SizedBox();
        },
      ),
    );
    return result;
  }

  List<String> labels(List<ChatListTabData> tabs) =>
      tabs.map((t) => t.label).toList();

  group('tab data', () {
    testWidgets('tabs mode with spaces and folders', (tester) async {
      expect(labels(await tabData(tester)), [
        'All chats',
        'Alpha',
        'Beta',
        'Unread',
        'Personal',
        'Groups',
      ]);
    });

    testWidgets('folders hidden after spaces when the setting is off', (
      tester,
    ) async {
      expect(labels(await tabData(tester, showFolders: false)), [
        'All chats',
        'Alpha',
        'Beta',
      ]);
    });

    testWidgets('no spaces: folders stay even when the setting is off', (
      tester,
    ) async {
      expect(labels(await tabData(tester, spaces: [], showFolders: false)), [
        'All chats',
        'Unread',
        'Personal',
        'Groups',
      ]);
    });

    testWidgets('switcher mode has no space tabs', (tester) async {
      expect(
        labels(await tabData(tester, mode: SpaceNavigationMode.switcher)),
        ['All', 'Unread', 'Personal', 'Groups'],
      );
    });

    testWidgets('counts come from countOf, never for All, hidden by setting', (
      tester,
    ) async {
      final shown = await tabData(tester, countOf: (_) => 7);
      expect(shown.map((t) => t.count), [0, 7, 7, 7, 7, 7]);
      final hidden = await tabData(
        tester,
        showCounts: false,
        countOf: (_) => 7,
      );
      expect(hidden.every((t) => t.count == 0), isTrue);
    });

    testWidgets('switcher mode counts All, tabs mode does not', (tester) async {
      final switcher = await tabData(
        tester,
        mode: SpaceNavigationMode.switcher,
        countOf: (_) => 7,
      );
      expect(switcher.map((t) => t.count), [7, 7, 7, 7]);
    });
  });

  group('tab bar', () {
    const tabs = [
      ChatListTabData(scope: ChatListScope(), label: 'All chats', count: 0),
      ChatListTabData(
        scope: ChatListScope(spaceId: '!a:x'),
        label: 'Alpha',
        count: 3,
        space: _spaceA,
      ),
      ChatListTabData(
        scope: ChatListScope(folder: FolderRef.unread),
        label: 'Unread',
        count: 120,
      ),
    ];

    Widget bar({
      ChatListScope? selected,
      ValueChanged<ChatListScope>? onSelect,
    }) => ChatListTabBar(
      client: client,
      tabs: tabs,
      selected: selected ?? const ChatListScope(),
      onSelect: onSelect ?? (_) {},
    );

    testWidgets('shows counts and caps them at 99+', (tester) async {
      await pumpGoldenWidget(tester, bar());
      expect(find.text('3'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('120'), findsNothing);
    });

    testWidgets('tapping a tab reports its scope', (tester) async {
      ChatListScope? tapped;
      await pumpGoldenWidget(tester, bar(onSelect: (s) => tapped = s));
      await tester.tap(find.text('Alpha'));
      expect(tapped, const ChatListScope(spaceId: '!a:x'));
    });

    testWidgets('semantics: selected state and unread count', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGoldenWidget(
        tester,
        bar(selected: const ChatListScope(spaceId: '!a:x')),
      );
      expect(
        tester.getSemantics(find.text('Alpha')),
        matchesSemantics(
          label: 'Alpha, 3 unread',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('All chats')).flagsCollection.isSelected,
        isNot(Tristate.isTrue),
      );
      handle.dispose();
    });

    testWidgets('every hit area is at least 44 px high', (tester) async {
      await pumpGoldenWidget(tester, bar());
      for (final tab in tabs) {
        final box = find.ancestor(
          of: find.text(tab.label),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(box).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(box).width, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('text scale 2.0 does not overflow', (tester) async {
      await pumpGoldenWidget(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: bar(),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('goldens in light, dark and RTL, RTL starts at the right', (
      tester,
    ) async {
      final selected = bar(selected: const ChatListScope(spaceId: '!a:x'));
      for (final variant in goldenVariants) {
        await pumpGoldenWidget(
          tester,
          selected,
          brightness: variant.brightness,
          rtl: variant.rtl,
          locale: variant.locale,
          size: const Size(400, 120),
        );
        if (variant.rtl) {
          final first = tester.getTopLeft(find.byType(InkWell).first).dx;
          final last = tester.getTopLeft(find.byType(InkWell).last).dx;
          expect(first, greaterThan(last));
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/chat_list_tabs_${variant.suffix}.png'),
        );
      }
    });
  });
}
