// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/pages/chat/chat_wallpaper.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient());

  group('dot grid', () {
    test('20 by 40 dots on 360 x 720, centred in 18 px cells', () {
      final dots = WallpaperDots.dotCenters(const Size(360, 720));
      expect(dots.length, 800);
      expect(dots.first, const Offset(9, 9));
      expect(dots[20], const Offset(9, 27));
      expect(dots[1], const Offset(27, 9));
    });

    test('the number of dots is capped', () {
      final dots = WallpaperDots.dotCenters(const Size(5400, 5400));
      expect(dots.length, lessThanOrEqualTo(AppChat.maxWallpaperDots));
    });

    test('a huge height with no columns returns at once (SEC I1)', () {
      final watch = Stopwatch()..start();
      expect(WallpaperDots.dotCenters(const Size(5, 1e10)), isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test('a huge height with one column is bounded by the cap (SEC I1)', () {
      final watch = Stopwatch()..start();
      final dots = WallpaperDots.dotCenters(const Size(18, 1e12));
      expect(dots.length, AppChat.maxWallpaperDots);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('empty or non-finite sizes give no dots', () {
      expect(WallpaperDots.dotCenters(Size.zero), isEmpty);
      expect(
        WallpaperDots.dotCenters(const Size(double.infinity, 10)),
        isEmpty,
      );
    });
  });

  testWidgets('default wallpaper paints the dot grid', (tester) async {
    await pumpGoldenWidget(
      tester,
      const ChatWallpaper(config: ApplicationAccountConfig()),
    );
    expect(find.byKey(ChatWallpaper.dotsKey), findsOneWidget);
  });

  testWidgets('a custom wallpaper replaces the dots', (tester) async {
    await pumpGoldenWidget(
      tester,
      ChatWallpaper(
        client: client,
        config: ApplicationAccountConfig(
          wallpaperUrl: Uri.parse('mxc://example.org/abc'),
          wallpaperOpacity: 0.5,
        ),
      ),
    );
    expect(find.byKey(ChatWallpaper.dotsKey), findsNothing);
    expect(find.byType(ImageFiltered), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('goldens in light and dark', (tester) async {
    for (final variant in goldenVariants.where((v) => !v.rtl)) {
      await pumpGoldenWidget(
        tester,
        const ChatWallpaper(config: ApplicationAccountConfig()),
        brightness: variant.brightness,
        size: const Size(180, 360),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/chat_wallpaper_${variant.suffix}.png'),
      );
    }
  });
}
