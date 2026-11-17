// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/appearance/chat_appearance.dart';
import 'package:fluffychat/utils/appearance/chat_appearance_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

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
    harness.room.roomAccountData.remove(RoomAppearance.type);
    await harness.tearDown();
  });

  void setRoomData(Map<String, Object?> content) {
    harness.room.roomAccountData[RoomAppearance.type] = BasicEvent(
      type: RoomAppearance.type,
      content: content,
    );
  }

  testWidgets('room data that smuggles a url makes no request and falls back', (
    tester,
  ) async {
    setRoomData({
      'v': 1,
      'preset': 'https://evil.example/wallpaper.png',
      'wallpaper_url': 'mxc://evil.example/abc',
      'corners': 'round',
    });
    await harness.open(tester);
    final resolved = resolveRoomAppearance(harness.room);
    expect(resolved.preset, 'default');
    expect(resolved.corners, BubbleCorners.round);
    expect(
      api.log.every((r) => r.url.host == 'fakeserver.notexisting'),
      isTrue,
      reason: api.log.map((r) => r.url.host).toSet().toString(),
    );
    expect(api.log.where((r) => r.url.path.contains('evil')), isEmpty);
    await harness.finish(tester);
  });

  testWidgets('oversized room data is ignored', (tester) async {
    setRoomData({'v': 1, 'preset': 'night', 'junk': 'x' * 2000});
    await harness.open(tester);
    expect(resolveRoomAppearance(harness.room).hasRoomOverride, isFalse);
    expect(resolveRoomAppearance(harness.room).preset, 'default');
    await harness.finish(tester);
  });

  testWidgets('a valid room document is applied to the open chat', (
    tester,
  ) async {
    setRoomData({'v': 1, 'preset': 'night', 'accent_hue': 25});
    await harness.open(tester);
    final resolved = resolveRoomAppearance(harness.room);
    expect(resolved.preset, 'night');
    expect(resolved.accentHue, 25);
    await harness.finish(tester);
  });
}
