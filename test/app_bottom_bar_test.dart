// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:fluffychat/widgets/layouts/app_bottom_bar.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';

const _size = Size(400, 220);

Widget _bar({
  required List<AppTab> tabs,
  AppTab selected = AppTab.chats,
  ValueChanged<AppTab>? onSelect,
}) => Stack(
  children: [
    Positioned.fill(
      child: Column(
        children: [
          for (var i = 0; i < 8; i++)
            Expanded(
              child: ColoredBox(
                color: i.isEven ? Colors.indigo : Colors.teal,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    ),
    Align(
      alignment: Alignment.bottomCenter,
      child: AppBottomBar(
        tabs: tabs,
        selected: selected,
        onSelect: onSelect ?? (_) {},
        profileAvatar: const CircleAvatar(
          radius: 12.5,
          backgroundColor: Colors.orange,
          child: Text('AL', style: TextStyle(fontSize: 9)),
        ),
      ),
    ),
  ],
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  final all = AppTab.visible(callsEnabled: true);
  final noCalls = AppTab.visible(callsEnabled: false);

  group('AppTab', () {
    test('Calls slot is hidden when calls are disabled', () {
      expect(all, AppTab.values);
      expect(noCalls, [AppTab.chats, AppTab.settings, AppTab.profile]);
    });

    test('path to tab mapping', () {
      expect(AppTab.forPath('/rooms'), AppTab.chats);
      expect(AppTab.forPath('/rooms/!abc:example.org'), AppTab.chats);
      expect(AppTab.forPath('/settings/security'), AppTab.settings);
      expect(AppTab.forPath('/profile'), AppTab.profile);
      expect(AppTab.forPath('/calls'), AppTab.calls);
      expect(AppTab.forPath('/roomsx'), isNull);
      expect(AppTab.forPath('/home'), isNull);
    });

    test('only tab roots show the bar', () {
      expect(AppTab.isRoot('/rooms'), isTrue);
      expect(AppTab.isRoot('/settings'), isTrue);
      expect(AppTab.isRoot('/rooms/!abc'), isFalse);
      expect(AppTab.isRoot('/settings/style'), isFalse);
    });
  });

  group('AppBottomBar', () {
    testWidgets('geometry follows DESIGN 5.1 / 7.1', (tester) async {
      await pumpGoldenWidget(tester, _bar(tabs: all), size: _size);
      final rect = tester.getRect(find.byType(GlassSurface));
      expect(rect.height, 68);
      expect(rect.left, 14);
      expect(rect.right, _size.width - 14);
      expect(_size.height - rect.bottom, 24);
      final items = find.byType(InkWell);
      expect(items, findsNWidgets(4));
      final widths = [
        for (var i = 0; i < 4; i++) tester.getSize(items.at(i)).width,
      ];
      expect(widths.every((w) => (w - widths.first).abs() < 0.01), isTrue);
    });

    testWidgets('every slot is at least 44 px', (tester) async {
      await pumpGoldenWidget(tester, _bar(tabs: noCalls), size: _size);
      final items = find.byType(InkWell);
      expect(items, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final size = tester.getSize(items.at(i));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('tapping a slot selects that tab', (tester) async {
      final tapped = <AppTab>[];
      await pumpGoldenWidget(
        tester,
        _bar(tabs: all, onSelect: tapped.add),
        size: _size,
      );
      await tester.tap(find.text('Settings'));
      await tester.tap(find.text('Calls'));
      await tester.tap(find.byType(CircleAvatar));
      expect(tapped, [AppTab.settings, AppTab.calls, AppTab.profile]);
    });

    testWidgets('selected slot is exposed to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGoldenWidget(
        tester,
        _bar(tabs: all, selected: AppTab.calls),
        size: _size,
      );
      for (final tab in all) {
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(RegExp('^${_label(tab)}\$')),
          ),
          isSemantics(
            label: _label(tab),
            isButton: true,
            hasTapAction: true,
            hasSelectedState: true,
            isSelected: tab == AppTab.calls,
          ),
          reason: '$tab',
        );
      }
      handle.dispose();
    });

    testWidgets('uses glass, solid when transparency is reduced', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, _bar(tabs: all), size: _size);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await AppSettings.reduceTransparency.setItem(true);
      await pumpGoldenWidget(tester, _bar(tabs: all), size: _size);
      expect(find.byType(BackdropFilter), findsNothing);
      await AppSettings.reduceTransparency.setItem(false);
    });

    testWidgets('RTL mirrors the order of the slots', (tester) async {
      await pumpGoldenWidget(tester, _bar(tabs: all), size: _size, rtl: true);
      expect(
        tester.getCenter(find.text('Chats')).dx,
        greaterThan(tester.getCenter(find.text('Settings')).dx),
      );
    });

    testWidgets('golden: four items, three items (light, dark, RTL)', (
      tester,
    ) async {
      await expectGoldenVariants(
        tester,
        'app_bottom_bar_4',
        _bar(tabs: all),
        size: _size,
      );
      await expectGoldenVariants(
        tester,
        'app_bottom_bar_3',
        _bar(tabs: noCalls, selected: AppTab.settings),
        size: _size,
      );
    });
  });
}

String _label(AppTab tab) => switch (tab) {
  AppTab.chats => 'Chats',
  AppTab.calls => 'Calls',
  AppTab.settings => 'Settings',
  AppTab.profile => 'Profile',
};
