// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/utils/crypto_identity.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
    api.getOverrides.clear();
    api.onRequest = null;
    loadCryptoIdentityConnected = (_) async => true;
  });
  tearDown(() async {
    loadCryptoIdentityConnected = defaultLoadCryptoIdentityConnected;
    await harness.tearDown();
  });

  const titles = [
    "Show when I'm typing",
    'Send read receipts',
    'Show online status',
    'Appear offline',
  ];

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  testWidgets('the privacy toggles show before any network answer', (
    tester,
  ) async {
    final never = Completer<void>();
    api.onRequest = (request) async {
      if (request.url.path.endsWith('/capabilities')) await never.future;
    };
    await harness.open(tester, path: '/settings/security');
    expect(find.byType(SettingsSecurity), findsOneWidget);
    for (final title in titles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    await harness.finish(tester);
  });

  testWidgets('all four are off on a fresh store and exist once', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings/security');
    expect(AppSettings.sendTypingNotifications.value, isFalse);
    expect(AppSettings.sendPublicReadReceipts.value, isFalse);
    expect(AppSettings.shareOnlineStatus.value, isFalse);
    expect(AppSettings.appearOffline.value, isFalse);
    expect(find.byType(AppSettingToggleRow), findsAtLeastNWidgets(4));
    for (final title in titles) {
      expect(find.text(title), findsOneWidget);
    }
    await harness.finish(tester);
  });

  testWidgets('groups follow the mockup order', (tester) async {
    await harness.open(tester, path: '/settings/security', height: 2600);
    double? last;
    for (final label in ['VISIBILITY', 'MESSAGES', 'ENCRYPTION', 'ACCOUNT']) {
      final finder = find.text(label, skipOffstage: false);
      expect(finder, findsOneWidget, reason: label);
      final y = tester.getTopLeft(finder).dy;
      if (last != null) expect(y, greaterThan(last), reason: label);
      last = y;
    }
    await harness.finish(tester);
  });

  testWidgets('key backup shows its state', (tester) async {
    await harness.open(tester, path: '/settings/security', height: 2600);
    await harness.settle(tester);
    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, 'Chat backup'),
        matching: find.text('On'),
      ),
      findsOneWidget,
    );
    await harness.finish(tester);
  });

  testWidgets(
    'the default timer row says so when the server has no retention',
    (tester) async {
      api.getOverrides['/versions'] = {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc1763': false},
      };
      await harness.open(tester, path: '/settings/security', height: 2600);
      await harness.settle(tester);
      expect(
        find.text("Your server doesn't support disappearing messages."),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('default_retention_row')));
      await harness.settle(tester);
      expect(
        find.byKey(const ValueKey('default_retention_604800')),
        findsNothing,
      );
      await harness.finish(tester);
    },
  );

  group('the default timer row and the server', () {
    const unknown =
        "We couldn't check whether your server supports disappearing messages.";
    const unsupported = "Your server doesn't support disappearing messages.";

    Finder rowText(String text) => find.descendant(
      of: find.byKey(const ValueKey('default_retention_row')),
      matching: find.text(text),
    );

    testWidgets('an unreadable server is unknown, not unsupported', (
      tester,
    ) async {
      api.onRequest = (request) async {
        if (request.url.path.endsWith('/versions')) {
          throw Exception('offline');
        }
      };
      await harness.open(tester, path: '/settings/security', height: 2600);
      await harness.settle(tester, rounds: 10);
      expect(rowText(unknown), findsOneWidget);
      expect(rowText(unsupported), findsNothing);
      await tester.tap(find.byKey(const ValueKey('default_retention_row')));
      await harness.settle(tester);
      expect(
        find.byKey(const ValueKey('default_retention_604800')),
        findsNothing,
      );
      await harness.finish(tester);
    });

    testWidgets('while the server is still being asked nothing is claimed', (
      tester,
    ) async {
      final never = Completer<void>();
      api.onRequest = (request) async {
        if (request.url.path.endsWith('/versions')) await never.future;
      };
      await harness.open(tester, path: '/settings/security', height: 2600);
      await harness.settle(tester, rounds: 4);
      expect(rowText(unknown), findsNothing);
      expect(rowText(unsupported), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('the answer arrives later: the row is enabled without a '
        'reload of the page', (tester) async {
      final answer = Completer<void>();
      api.getOverrides['/versions'] = {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc1763': true},
      };
      api.onRequest = (request) async {
        if (request.url.path.endsWith('/versions')) await answer.future;
      };
      await harness.open(tester, path: '/settings/security', height: 2600);
      await harness.settle(tester, rounds: 4);
      await tester.tap(find.byKey(const ValueKey('default_retention_row')));
      await harness.settle(tester);
      expect(
        find.byKey(const ValueKey('default_retention_604800')),
        findsNothing,
      );
      answer.complete();
      await harness.settle(tester, rounds: 8);
      await tester.tap(find.byKey(const ValueKey('default_retention_row')));
      await harness.settle(tester);
      expect(
        find.byKey(const ValueKey('default_retention_604800')),
        findsOneWidget,
      );
      await harness.finish(tester);
    });

    testWidgets('picking a timer changes the value on the row at once', (
      tester,
    ) async {
      api.getOverrides['/versions'] = {
        'versions': ['v1.1'],
        'unstable_features': {'org.matrix.msc1763': true},
      };
      await harness.open(tester, path: '/settings/security', height: 2600);
      await harness.settle(tester, rounds: 10);
      expect(rowText('Off'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('default_retention_row')));
      await harness.settle(tester);
      await tester.tap(find.byKey(const ValueKey('default_retention_604800')));
      await harness.settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await harness.settle(tester);
      expect(rowText('1 week'), findsOneWidget);
      expect(rowText('Off'), findsNothing);
      await harness.finish(tester);
    });
  });

  testWidgets('a rebuild of the page does not ask for the capabilities again', (
    tester,
  ) async {
    await harness.open(tester, path: '/settings/security', height: 2600);
    await harness.settle(tester, rounds: 8);
    final before = api.requests('/capabilities').length;
    cryptoIdentityRevision.value++;
    await harness.settle(tester, rounds: 4);
    expect(api.requests('/capabilities').length, before);
    await harness.finish(tester);
  });

  testWidgets('with retention supported the row opens the sheet', (
    tester,
  ) async {
    api.getOverrides['/versions'] = {
      'versions': ['v1.1'],
      'unstable_features': {'org.matrix.msc1763': true},
    };
    await harness.open(tester, path: '/settings/security', height: 2600);
    await harness.settle(tester, rounds: 10);
    await tester.tap(find.byKey(const ValueKey('default_retention_row')));
    await harness.settle(tester);
    await tester.tap(find.byKey(const ValueKey('default_retention_604800')));
    await harness.settle(tester);
    expect(AppSettings.defaultDisappearSeconds.value, 604800);
    await harness.finish(tester);
  });

  testWidgets('change password is hidden when the server forbids it', (
    tester,
  ) async {
    api.getOverrides['/capabilities'] = {
      'capabilities': {
        'm.change_password': {'enabled': false},
      },
    };
    await harness.open(tester, path: '/settings/security', height: 2600);
    await harness.settle(tester, rounds: 8);
    expect(find.text('Change password'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('change password is shown when the server allows it', (
    tester,
  ) async {
    api.getOverrides['/capabilities'] = {
      'capabilities': {
        'm.change_password': {'enabled': true},
      },
    };
    await harness.open(tester, path: '/settings/security', height: 2600);
    await harness.settle(tester, rounds: 8);
    expect(find.text('Change password'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('change password is shown when capabilities cannot be read', (
    tester,
  ) async {
    api.onRequest = (request) async {
      if (request.url.path.endsWith('/capabilities')) {
        throw Exception('offline');
      }
    };
    await harness.open(tester, path: '/settings/security', height: 2600);
    await harness.settle(tester, rounds: 8);
    expect(find.text('Change password'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('320x480 scrolls to the last row without overflow', (
    tester,
  ) async {
    await harness.open(
      tester,
      path: '/settings/security',
      width: 320,
      height: 480,
    );
    await scrollTo(tester, find.text('Delete account'));
    expect(tester.takeException(), isNull);
    await harness.finish(tester);
  });
}
