// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/pages/new_private_chat/scan_confirm_sheet.dart';
import 'package:fluffychat/pages/space_overview/space_overview.dart';
import 'package:fluffychat/pages/space_overview/space_overview_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';
import 'utils/recording_api.dart';

/// W05 N1: every page and sheet with an input has to work on a small screen
/// with the keyboard open and large text.
void main() {
  final api = RecordingApi();
  final harness = ChatPageHarness(httpClient: api);

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    harness.resetRooms();
    api.clear();
    api.api['POST']!['/client/v3/user_directory/search'] = (_) => {
      'results': [
        for (var n = 0; n < 12; n++)
          {'user_id': '@user$n:example.org', 'display_name': 'User number $n'},
      ],
      'limited': false,
    };
    api.getResponder = (url) => url.path.endsWith('/hierarchy')
        ? {
            'rooms': [
              for (var n = 0; n < 12; n++)
                {
                  'room_id': '!r$n:example.org',
                  'name': 'A room with a rather long name number $n',
                  'num_joined_members': 5,
                  'children_state': <Object?>[],
                  'guest_can_join': false,
                  'world_readable': false,
                },
            ],
          }
        : null;
  });
  tearDown(harness.tearDown);

  void smallScreen(WidgetTester tester, {double scale = 1.0}) {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'the new message page at 320x480, keyboard open, text x$scale',
      (tester) async {
        smallScreen(tester, scale: scale);
        await harness.open(
          tester,
          width: 320,
          height: 480,
          path: '/rooms/newprivatechat',
        );
        final field = tester.getRect(find.byKey(NewPrivateChatView.fieldKey));
        expect(field.bottom, lessThanOrEqualTo(480 - 300 + 1));
        expect(field.height, greaterThanOrEqualTo(44));
        await tester.enterText(find.byKey(NewPrivateChatView.fieldKey), 'user');
        await tester.pump(const Duration(milliseconds: 600));
        await harness.settle(tester, rounds: 3);
        await tester.scrollUntilVisible(
          find.text('User number 11'),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(NewPrivateChatView.listKey),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
        await harness.finish(tester);
      },
    );

    testWidgets(
      'the actions of the new message page scroll at 320x480, text x$scale',
      (tester) async {
        smallScreen(tester, scale: scale);
        await harness.open(
          tester,
          width: 320,
          height: 480,
          path: '/rooms/newprivatechat',
        );
        await tester.scrollUntilVisible(
          find.byKey(NewPrivateChatView.inviteKey),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(NewPrivateChatView.listKey),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final rect = tester.getRect(find.byKey(NewPrivateChatView.inviteKey));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
        await harness.finish(tester);
      },
    );

    testWidgets('the new group page at 320x480, keyboard open, text x$scale', (
      tester,
    ) async {
      smallScreen(tester, scale: scale);
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: '/rooms/newgroup',
      );
      await tester.enterText(find.byType(TextField).first, 'Project room');
      await tester.pump();
      final field = tester.getRect(find.byType(TextField).first);
      expect(field.top, greaterThanOrEqualTo(0));
      expect(field.bottom, lessThanOrEqualTo(480 - 300 + 1));
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });

    testWidgets('the space overview at 320x480, keyboard open, text x$scale', (
      tester,
    ) async {
      smallScreen(tester, scale: scale);
      await harness.open(
        tester,
        width: 320,
        height: 480,
        path: '/rooms/space/${Uri.encodeComponent('!space:example.org')}',
      );
      expect(find.byType(SpaceOverview), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('number 11'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(SpaceOverviewView.listKey),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await harness.finish(tester);
    });
  }

  testWidgets('the scan confirmation at 320x480 with large text and keyboard', (
    tester,
  ) async {
    smallScreen(tester, scale: 2.0);
    await harness.open(
      tester,
      width: 320,
      height: 480,
      path: '/rooms/newprivatechat',
    );
    final controller = tester.state<NewPrivateChatController>(
      find.byType(NewPrivateChat),
    );
    unawaited(
      controller.handleScan(
        'https://matrix.to/#/!room:example.org?via=a.example&via=b.example',
      ),
    );
    await harness.settle(tester, rounds: 3);
    expect(find.byType(ScanConfirmSheet), findsOneWidget);
    await tester.ensureVisible(find.byKey(ScanConfirmSheet.openKey));
    await tester.pump();
    final open = tester.getRect(find.byKey(ScanConfirmSheet.openKey));
    expect(open.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });
}
