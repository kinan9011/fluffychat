// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show MatrixSdkDatabase, Profile;
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/settings/settings.dart';
import 'package:odango/pages/settings/settings_view.dart';
import 'package:odango/pages/settings_appearance/settings_appearance.dart';

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
    await (harness.client.database as MatrixSdkDatabase)
        .clearCustomCacheObjects();
  });
  tearDown(harness.tearDown);

  test('unread label caps at 99+', () {
    expect(SettingsView.unreadLabel(3), '3');
    expect(SettingsView.unreadLabel(99), '99');
    expect(SettingsView.unreadLabel(100), '99+');
  });

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );

  testWidgets('groups appear in the planned order and there is no Calls row', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings', height: 2400);
    expect(find.byType(Settings), findsOneWidget);
    final order = [
      'ACCOUNTS',
      'Add account',
      'Chat backup',
      'Appearance',
      'Notifications',
      'Chats',
      'Privacy and security',
      'Devices',
      'Emotes and stickers',
      'Homeserver',
      'Logout',
    ];
    double? last;
    for (final label in order) {
      final finder = find.text(label, skipOffstage: false);
      expect(finder, findsAtLeastNWidgets(1), reason: label);
      final y = tester.getTopLeft(finder.first).dy;
      if (last != null) expect(y, greaterThan(last), reason: label);
      last = y;
    }
    expect(find.text('Calls and video'), findsNothing);
    expect(find.text('Security'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('the account row shows the unread count and the active mark', (
    tester,
  ) async {
    harness.room.notificationCount = 3;
    await harness.open(tester, path: '/settings', height: 1600);
    final rowKey = ValueKey('settings_account_${harness.client.userID}');
    expect(find.byKey(rowKey), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(rowKey), matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(rowKey),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    harness.room.notificationCount = 0;
    await harness.finish(tester);
  });

  testWidgets('Appearance opens the appearance page', (tester) async {
    await harness.open(tester, path: '/settings');
    await tester.tap(find.text('Appearance'));
    await harness.settle(tester);
    expect(find.byType(SettingsAppearance), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('320x480 scrolls to the logout row without overflow', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings', width: 320, height: 480);
    await scrollTo(tester, find.text('Logout'));
    expect(tester.takeException(), isNull);
    expect(find.text('Logout'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('the settings root has the profile QR button', (tester) async {
    await harness.open(tester, path: '/settings');
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a rebuild keeps the futures of the account rows', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings', height: 1600);
    await harness.settle(tester, rounds: 6);
    Object? profileFuture() => tester
        .widget<FutureBuilder<Profile?>>(find.byType(FutureBuilder<Profile?>))
        .future;
    Object? manageFuture() => tester
        .widget<FutureBuilder<Uri?>>(find.byType(FutureBuilder<Uri?>))
        .future;
    final profile = profileFuture();
    final manage = manageFuture();
    // ignore: invalid_use_of_protected_member
    tester.state<SettingsController>(find.byType(Settings)).setState(() {});
    await harness.settle(tester, rounds: 4);
    expect(profileFuture(), same(profile));
    expect(manageFuture(), same(manage));
    await harness.finish(tester);
  });

  testWidgets('name and MXID in the profile card are 44 px tall targets', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings', height: 1600);
    await harness.settle(tester, rounds: 6);
    final column = find
        .ancestor(
          of: find.text('@test:fakeServer.notExisting'),
          matching: find.byType(Column),
        )
        .first;
    final targets = find.descendant(of: column, matching: find.byType(InkWell));
    expect(targets, findsNWidgets(2));
    for (final target in targets.evaluate()) {
      expect(
        (target.renderObject! as RenderBox).size.height,
        greaterThanOrEqualTo(44),
      );
    }
    await harness.finish(tester);
  });
}
