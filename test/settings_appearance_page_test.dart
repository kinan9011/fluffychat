// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/settings_appearance/settings_appearance.dart';
import 'package:odango/utils/appearance/chat_appearance.dart';
import 'package:odango/utils/appearance/wallpaper_store.dart';
import 'package:odango/widgets/settings/settings_segmented.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    api.clear();
  });
  tearDown(() async {
    SettingsAppearanceController.storeOverride = null;
    SettingsAppearanceController.pickPhotoOverride = null;
    await harness.tearDown();
  });

  String roomPath() => '/rooms/${harness.room.id}/appearance';

  List<RecordedRequest> accountDataWrites() => api
      .requests(RoomAppearance.type, method: 'PUT')
      .where((r) => r.path.contains('/rooms/'))
      .toList();

  testWidgets('opened from a chat the scope switch shows that chat', (
    tester,
  ) async {
    await harness.open(tester, path: roomPath());
    expect(find.byType(SettingsAppearance), findsOneWidget);
    expect(
      find.byKey(SettingsSegmented.segmentKey(AppearanceScope.all)),
      findsOne,
    );
    expect(
      find.byKey(SettingsSegmented.segmentKey(AppearanceScope.room)),
      findsOne,
    );
    await harness.finish(tester);
  });

  testWidgets('from the settings there is no scope switch', (tester) async {
    await harness.open(tester, path: '/settings/appearance');
    expect(find.byType(SettingsAppearance), findsOneWidget);
    expect(
      find.byKey(SettingsSegmented.segmentKey(AppearanceScope.room)),
      findsNothing,
    );
    await harness.finish(tester);
  });

  testWidgets('a wallpaper tap in chat scope writes the exact document', (
    tester,
  ) async {
    await harness.open(tester, path: roomPath());
    await tester.tap(find.byKey(const ValueKey('wallpaper_sunset')));
    await harness.settle(tester);
    final writes = accountDataWrites();
    expect(writes, hasLength(1));
    expect(writes.single.json, {'v': 1, 'preset': 'sunset'});
    expect(AppSettings.chatWallpaperPreset.value, 'default');
    await harness.finish(tester);
  });

  testWidgets('a second change keeps the first one in the document', (
    tester,
  ) async {
    await harness.open(tester, path: roomPath());
    await tester.tap(find.byKey(const ValueKey('wallpaper_night')));
    await harness.settle(tester);
    await tester.tap(
      find.byKey(SettingsSegmented.segmentKey(BubbleCorners.round)),
    );
    await harness.settle(tester);
    expect(accountDataWrites().last.json, {
      'v': 1,
      'preset': 'night',
      'corners': 'round',
    });
    await harness.finish(tester);
  });

  testWidgets('in all chats scope the change is local and sends nothing', (
    tester,
  ) async {
    await harness.open(tester, path: roomPath());
    await tester.tap(
      find.byKey(SettingsSegmented.segmentKey(AppearanceScope.all)),
    );
    await tester.pump();
    final round = find.byKey(SettingsSegmented.segmentKey(BubbleCorners.round));
    await tester.scrollUntilVisible(
      round,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(round);
    await tester.pump();
    await tester.tap(round);
    await harness.settle(tester);
    expect(AppSettings.bubbleCorners.value, 'round');
    expect(accountDataWrites(), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('use settings for all chats clears the room document', (
    tester,
  ) async {
    await harness.open(tester, path: roomPath());
    await tester.tap(find.byKey(const ValueKey('wallpaper_meadow')));
    await harness.settle(tester);
    await tester.scrollUntilVisible(
      find.text('Use settings for all chats'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Use settings for all chats'));
    await harness.settle(tester);
    expect(accountDataWrites().last.json, <String, Object?>{});
    await harness.finish(tester);
  });

  testWidgets('text size 24 stores a factor of 1.5', (tester) async {
    await harness.open(tester, path: '/settings/appearance');
    final slider = tester.widget<Slider>(find.byType(Slider).last);
    slider.onChanged!(24);
    await harness.settle(tester);
    expect(AppSettings.fontSizeFactor.value, 1.5);
    await harness.finish(tester);
  });

  testWidgets('bubble corners persist in all chats scope', (tester) async {
    await harness.open(tester, path: '/settings/appearance');
    final sharp = find.byKey(SettingsSegmented.segmentKey(BubbleCorners.sharp));
    await tester.scrollUntilVisible(
      sharp,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(sharp);
    await tester.pump();
    await tester.tap(sharp);
    await harness.settle(tester);
    expect(AppSettings.bubbleCorners.value, 'sharp');
    await harness.finish(tester);
  });

  testWidgets('a room that is gone closes the page', (tester) async {
    await harness.open(tester, path: '/rooms/!gone:example.com/appearance');
    await harness.settle(tester);
    expect(find.byType(SettingsAppearance), findsNothing);
    await harness.finish(tester);
  });

  for (final path in [null, '/settings/appearance']) {
    testWidgets('320x480 has no overflow (${path ?? 'chat'})', (tester) async {
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: path ?? roomPath(),
      );
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });
  }

  group('custom wallpaper', () {
    late Directory dir;

    Uint8List photo() {
      final image = img.Image(width: 64, height: 64);
      img.fill(image, color: img.ColorRgb8(20, 120, 200));
      return img.encodeJpg(image);
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wallpaper_page_test');
      SettingsAppearanceController.storeOverride = LocalWallpaperStore(
        baseDir: () async => dir,
      );
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    testWidgets('a picked photo is stored locally and nothing is sent', (
      tester,
    ) async {
      SettingsAppearanceController.pickPhotoOverride = (_) async => photo();
      await harness.open(tester, path: '/settings/appearance');
      api.clear();
      await tester.tap(find.byKey(const ValueKey('wallpaper_custom')));
      await harness.settle(tester, rounds: 30);
      expect(AppSettings.chatWallpaperLocal.value, isTrue);
      expect(
        dir.listSync(recursive: true).whereType<File>().map((f) => f.path),
        ['${dir.path}/wallpapers/custom.jpg'],
      );
      expect(api.log.where((r) => r.method != 'GET'), isEmpty);
      expect(api.requests('upload'), isEmpty);
      await harness.finish(tester);
    });

    testWidgets('a file that is not a photo is refused and not stored', (
      tester,
    ) async {
      SettingsAppearanceController.pickPhotoOverride = (_) async =>
          Uint8List.fromList('hello'.codeUnits);
      await harness.open(tester, path: '/settings/appearance');
      await tester.tap(find.byKey(const ValueKey('wallpaper_custom')));
      await harness.settle(tester);
      expect(AppSettings.chatWallpaperLocal.value, isFalse);
      expect(dir.listSync(recursive: true), isEmpty);
      expect(find.text("That file isn't a photo this app can use."), findsOne);
      await harness.finish(tester);
    });

    testWidgets('the custom tile is absent in chat scope', (tester) async {
      await harness.open(tester, path: roomPath());
      expect(find.byKey(const ValueKey('wallpaper_custom')), findsNothing);
      await harness.finish(tester);
    });
  });
}
