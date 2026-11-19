// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat_list/chat_list_top_bar.dart';
import 'package:odango/pages/chat_list/space_switcher.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;

  setUpAll(() async => client = await prepareTestClient());

  var profileTaps = 0;
  var searchTaps = 0;

  setUp(() {
    profileTaps = 0;
    searchTaps = 0;
  });

  Widget bar({Widget? chip, SyncStatusUpdate? status, String? title}) =>
      ChatListTopBar(
        title: title ?? AppSettings.applicationName.value,
        avatar: const CircleAvatar(
          radius: 17.5,
          backgroundColor: Colors.orange,
          child: Text('AL'),
        ),
        onProfile: () => profileTaps++,
        onSearch: () => searchTaps++,
        overflow: const IconButton(
          onPressed: null,
          icon: Icon(Icons.more_vert_rounded),
        ),
        spaceChip: chip,
        syncStatus: status,
      );

  testWidgets('the wordmark is the configured application name', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, const SizedBox());
    await AppSettings.applicationName.setItem('Acme');
    await pumpGoldenWidget(tester, bar());
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Odango'), findsNothing);
  });

  testWidgets('avatar opens the profile, search starts the search', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, bar());
    await tester.tap(find.bySemanticsLabel('Open profile'));
    await tester.tap(find.byTooltip('Search'));
    expect([profileTaps, searchTaps], [1, 1]);
  });

  testWidgets('targets are at least 44 px', (tester) async {
    await pumpGoldenWidget(tester, bar());
    final search = tester.getSize(
      find.widgetWithIcon(IconButton, Icons.search_rounded),
    );
    expect(search.width, greaterThanOrEqualTo(44));
    expect(search.height, greaterThanOrEqualTo(44));
  });

  testWidgets('switcher mode shows the chip instead of the wordmark', (
    tester,
  ) async {
    await pumpGoldenWidget(
      tester,
      bar(
        chip: SpaceSwitcherChip(
          client: client,
          spaces: const [],
          selectedSpaceId: null,
          onSelect: (_) {},
          onCreateSpace: () {},
          onExplore: () {},
        ),
      ),
    );
    expect(find.byType(SpaceSwitcherChip), findsOneWidget);
    expect(find.text(AppSettings.applicationName.value), findsNothing);
  });

  testWidgets('sync status and progress show only while syncing', (
    tester,
  ) async {
    await pumpGoldenWidget(tester, bar());
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await pumpGoldenWidget(
      tester,
      bar(status: const SyncStatusUpdate(SyncStatus.processing, progress: 0.5)),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Synchronizing… (50%)'), findsOneWidget);
  });

  testWidgets('goldens in light, dark and RTL', (tester) async {
    await expectGoldenVariants(
      tester,
      'chat_list_top_bar',
      bar(status: const SyncStatusUpdate(SyncStatus.processing, progress: 0.4)),
      size: const Size(400, 110),
    );
  });
}
