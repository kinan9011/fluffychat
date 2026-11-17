// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:fluffychat/widgets/settings/settings_segmented.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/golden.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 800),
    bool rtl = false,
    bool disableAnimations = false,
  }) async {
    await pumpGoldenWidget(
      tester,
      MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: child,
      ),
      rtl: rtl,
      size: size,
    );
  }

  group('SettingsRow', () {
    testWidgets('is 50 high without and 62 with a subtitle', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsRow(key: const Key('a'), icon: Icons.palette, title: 'A'),
            SettingsRow(
              key: const Key('b'),
              icon: Icons.palette,
              title: 'B',
              subtitle: 'sub',
            ),
          ],
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('a'))).height,
        AppSettingsLayout.rowHeight,
      );
      expect(
        tester.getSize(find.byKey(const Key('b'))).height,
        greaterThanOrEqualTo(AppSettingsLayout.rowHeightSub),
      );
    });

    testWidgets('keeps a 44 px tap target on a 320 px wide screen', (
      tester,
    ) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsRow(
              key: const Key('a'),
              icon: Icons.palette,
              title: 'A very long title that has to wrap on a narrow screen',
              value: 'value',
              onTap: () {},
            ),
          ],
        ),
        size: const Size(320, 480),
      );
      final size = tester.getSize(find.byKey(const Key('a')));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('divider starts after the icon and none follows the last row', (
      tester,
    ) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsRow(icon: Icons.palette, title: 'A'),
            SettingsRow(icon: Icons.palette, title: 'B'),
            SettingsRow(icon: Icons.palette, title: 'C'),
          ],
        ),
      );
      final dividers = find.byType(SettingsDivider);
      expect(dividers, findsNWidgets(2));
      final card = tester.getTopLeft(find.byType(SettingsGroup)).dx;
      final line = find.descendant(
        of: dividers.first,
        matching: find.byType(ColoredBox),
      );
      expect(tester.getTopLeft(line).dx - card, AppSettingsLayout.dividerInset);
    });

    testWidgets('divider inset mirrors in RTL', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsRow(icon: Icons.palette, title: 'A'),
            SettingsRow(icon: Icons.palette, title: 'B'),
          ],
        ),
        rtl: true,
      );
      final groupBox = tester.getRect(find.byType(SettingsGroup));
      final divider = tester.getRect(
        find.descendant(
          of: find.byType(SettingsDivider).first,
          matching: find.byType(ColoredBox),
        ),
      );
      expect(groupBox.right - divider.right, AppSettingsLayout.dividerInset);
    });

    testWidgets('chevron mirrors in RTL', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [SettingsRow(icon: Icons.palette, title: 'A', onTap: () {})],
        ),
        rtl: true,
      );
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.chevron_right_rounded),
      );
      expect(icon.textDirection ?? TextDirection.rtl, TextDirection.rtl);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right_rounded),
          matching: find.byType(Directionality),
        ),
        findsWidgets,
      );
    });

    testWidgets('exposes a button with title and value to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.palette,
              title: 'Appearance',
              value: 'Dark',
              onTap: () {},
            ),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.text('Appearance')),
        isSemantics(
          label: 'Appearance, Dark',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('tap calls onTap', (tester) async {
      var taps = 0;
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsRow(icon: Icons.palette, title: 'A', onTap: () => taps++),
          ],
        ),
      );
      await tester.tap(find.text('A'));
      expect(taps, 1);
    });
  });

  group('destructive row contrast', () {
    test('red on surf is at least 4.5:1 in both themes for every hue', () {
      for (var hue = 0; hue < 360; hue += 5) {
        final light = AppTokens.light(hue: hue.toDouble());
        final dark = AppTokens.dark(hue: hue.toDouble());
        expect(
          wcagContrast8(light.red, light.surf),
          greaterThanOrEqualTo(4.5),
          reason: 'light hue $hue',
        );
        expect(
          wcagContrast8(dark.red, dark.surf),
          greaterThanOrEqualTo(4.5),
          reason: 'dark hue $hue',
        );
      }
    });
  });

  group('SettingsToggleRow', () {
    testWidgets('switch is 46x28 with a 22 knob', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [SettingsToggleRow(title: 'T', value: true, onChanged: (_) {})],
        ),
      );
      expect(
        tester.getSize(find.byKey(SettingsToggleRow.switchKey)),
        const Size(
          AppSettingsLayout.switchWidth,
          AppSettingsLayout.switchHeight,
        ),
      );
      expect(
        tester.getSize(find.byKey(SettingsToggleRow.knobKey)),
        const Size(AppSettingsLayout.knob, AppSettingsLayout.knob),
      );
    });

    testWidgets('semantics report the toggled state and flip on tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var value = false;
      late StateSetter set;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return SettingsGroup(
              rows: [
                SettingsToggleRow(
                  title: 'Typing',
                  value: value,
                  onChanged: (v) => value = v,
                ),
              ],
            );
          },
        ),
      );
      expect(
        tester.getSemantics(find.text('Typing')),
        isSemantics(label: 'Typing', hasToggledState: true, isToggled: false),
      );
      await tester.tap(find.text('Typing'));
      set(() {});
      await tester.pump();
      expect(value, isTrue);
      expect(
        tester.getSemantics(find.text('Typing')),
        isSemantics(label: 'Typing', hasToggledState: true, isToggled: true),
      );
      handle.dispose();
    });

    testWidgets('disabled row ignores taps and is dimmed', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            const SettingsToggleRow(
              title: 'T',
              subtitle: 'why',
              value: false,
              onChanged: null,
            ),
          ],
        ),
      );
      await tester.tap(find.text('T'));
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(find.byKey(SettingsToggleRow.opacityKey))
            .opacity,
        lessThan(1),
      );
    });

    testWidgets('knob does not animate under reduce motion', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            SettingsToggleRow(title: 'T', value: false, onChanged: (_) {}),
          ],
        ),
        disableAnimations: true,
      );
      final align = tester.widget<AnimatedAlign>(
        find.byKey(SettingsToggleRow.knobAlignKey),
      );
      expect(align.duration, Duration.zero);
    });

    testWidgets('AppSettingToggleRow follows the setting and writes it', (
      tester,
    ) async {
      await pump(
        tester,
        SettingsGroup(
          rows: [
            AppSettingToggleRow(
              title: 'Read receipts',
              setting: AppSettings.sendPublicReadReceipts,
              defaultValue: AppSettings.sendPublicReadReceipts.defaultValue,
            ),
          ],
        ),
      );
      expect(AppSettings.sendPublicReadReceipts.value, isFalse);
      await tester.tap(find.text('Read receipts'));
      await tester.pumpAndSettle();
      expect(AppSettings.sendPublicReadReceipts.value, isTrue);
      await tester.tap(find.text('Read receipts'));
      await tester.pumpAndSettle();
      expect(AppSettings.sendPublicReadReceipts.value, isFalse);
    });
  });

  group('SettingsSegmented', () {
    testWidgets('selected segment is reported and tapping changes it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var value = 'a';
      await pump(
        tester,
        SettingsSegmented<String>(
          items: const [('a', 'All'), ('b', 'Only here')],
          value: value,
          onChanged: (v) => value = v,
        ),
      );
      expect(
        tester.getSemantics(find.text('All')),
        isSemantics(label: 'All', isSelected: true, isButton: true),
      );
      await tester.tap(find.text('Only here'));
      expect(value, 'b');
      handle.dispose();
    });

    testWidgets('segments are at least 34 high', (tester) async {
      await pump(
        tester,
        SettingsSegmented<String>(
          items: const [('a', 'All'), ('b', 'Only here')],
          value: 'a',
          onChanged: (_) {},
        ),
      );
      expect(
        tester.getSize(find.byKey(SettingsSegmented.segmentKey('a'))).height,
        greaterThanOrEqualTo(34),
      );
    });
  });

  group('SettingsScaffold', () {
    testWidgets('scrolls on a 320x480 screen without overflow', (tester) async {
      await pump(
        tester,
        SettingsScaffold(
          title: 'Privacy and security',
          subtitle: 'sub',
          children: [
            for (var i = 0; i < 20; i++)
              SettingsGroup(
                header: 'Group $i',
                rows: [
                  SettingsRow(
                    icon: Icons.palette,
                    title: 'Row $i',
                    onTap: () {},
                  ),
                ],
              ),
          ],
        ),
        size: const Size(320, 480),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(find.text('Row 19'), findsOneWidget);
    });

    testWidgets('shows a back button on narrow screens', (tester) async {
      await pump(tester, const SizedBox(), size: const Size(400, 800));
      unawaited(
        Navigator.of(tester.element(find.byType(SizedBox).first)).push(
          MaterialPageRoute<void>(
            builder: (_) => const SettingsScaffold(title: 'T', children: []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(SettingsScaffold.backKey), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
    });
  });

  group('goldens', () {
    testWidgets('settings widgets', (tester) async {
      await expectGoldenVariants(
        tester,
        'settings_widgets',
        SettingsScaffold(
          title: 'Settings',
          children: [
            SettingsGroup(
              header: 'Visibility',
              footer: 'Footer text that explains the group.',
              rows: [
                SettingsToggleRow(
                  icon: Icons.done_all_rounded,
                  title: 'Send read receipts',
                  subtitle: 'Off: others will not see when you read',
                  value: false,
                  onChanged: (_) {},
                ),
                SettingsToggleRow(
                  icon: Icons.keyboard_rounded,
                  title: 'Show when I am typing',
                  value: true,
                  onChanged: (_) {},
                ),
                SettingsRow(
                  icon: Icons.timer_rounded,
                  title: 'Default disappearing timer',
                  value: 'Off',
                  onTap: () {},
                ),
                SettingsRow(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  destructive: true,
                  showChevron: false,
                  onTap: () {},
                ),
              ],
            ),
            SettingsSegmented<String>(
              items: const [('a', 'All chats'), ('b', 'Only here')],
              value: 'b',
              onChanged: (_) {},
            ),
          ],
        ),
        size: const Size(400, 640),
      );
    });
  });
}
