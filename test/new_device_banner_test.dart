// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/new_device_banner.dart';
import 'package:fluffychat/utils/chat/new_device_banner_model.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/chat_page_harness.dart';
import 'utils/golden.dart';
import 'utils/test_client.dart';

void main() {
  group('the banner widget', () {
    setUpAll(prepareTestClient);

    Widget banner({
      String name = 'Kim',
      VoidCallback? onVerify,
      VoidCallback? onDismiss,
      double height = 56,
    }) => NewDeviceBanner(
      name: name,
      height: height,
      onVerify: onVerify ?? () {},
      onDismiss: onDismiss ?? () {},
    );

    testWidgets('says who signed in and offers Verify and close', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, banner());
      expect(find.text('\u2068Kim\u2069'), findsOneWidget);
      expect(find.text('Signed in on a new device'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('a hostile name cannot hide the warning (SEC M1)', (
      tester,
    ) async {
      final hostile = '\n\n\n\u202Eevil\u2067' * 20;
      await pumpGoldenWidget(tester, banner(name: hostile));
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .join('|');
      expect(shown.contains('\n'), isFalse);
      expect(shown.contains('\u202E'), isFalse);
      expect(shown.contains('\u2067'), isFalse);
      expect(find.text('Signed in on a new device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a name made of combining marks is bounded and clipped '
        '(SEC S-N1)', (tester) async {
      await pumpGoldenWidget(tester, banner(name: 'B${'\u0489' * 300}'));
      final name = find.textContaining('B');
      final text = tester.widget<Text>(name.first);
      expect(text.data!.length, lessThan(12));
      expect(
        find.ancestor(of: name.first, matching: find.byType(ClipRect)),
        findsWidgets,
      );
    });

    for (final width in [320.0, 400.0]) {
      testWidgets('the widest name still leaves the whole warning visible at '
          '$width px (SEC M1)', (tester) async {
        await pumpGoldenWidget(
          tester,
          banner(name: 'W' * 40),
          size: Size(width, 120),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Signed in on a new device'),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      });
    }

    testWidgets('the buttons call their callbacks and are 44 px', (
      tester,
    ) async {
      var verify = 0;
      var dismiss = 0;
      await pumpGoldenWidget(
        tester,
        banner(onVerify: () => verify++, onDismiss: () => dismiss++),
      );
      expect(
        tester.getSize(find.byTooltip('Close')).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('Verify'));
      await tester.tap(find.byTooltip('Close'));
      expect([verify, dismiss], [1, 1]);
    });

    testWidgets('a hostile name is bounded to one line', (tester) async {
      await pumpGoldenWidget(tester, banner(name: 'W' * 5000));
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.textContaining('WWW'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('large text keeps the banner usable', (tester) async {
      await pumpGoldenWidget(tester, banner(height: 112));
      expect(tester.takeException(), isNull);
    });

    testWidgets('goldens in light, dark and RTL', (tester) async {
      for (final variant in goldenVariants) {
        await pumpGoldenWidget(
          tester,
          Padding(padding: const EdgeInsets.all(12), child: banner()),
          brightness: variant.brightness,
          rtl: variant.rtl,
          size: const Size(400, 90),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/new_device_banner_${variant.suffix}.png'),
        );
      }
    });
  });

  group('the banner never decides about trust', () {
    test('no trust call in the banner, its model or the page wiring', () {
      for (final path in [
        'lib/pages/chat/new_device_banner.dart',
        'lib/utils/chat/new_device_banner_model.dart',
        'lib/pages/chat/chat_view.dart',
      ]) {
        final source = File(path)
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        for (final identifier in [
          'setVerified',
          'setBlocked',
          'startVerification',
          'crossSigning',
          'openSSSS',
          'KeyVerification',
          'bootstrap',
          'SharedPreferences',
          'Logs()',
        ]) {
          expect(
            source,
            isNot(contains(identifier)),
            reason: '$path $identifier',
          );
        }
      }
    });
  });

  group('in the conversation', () {
    final harness = ChatPageHarness();

    setUpAll(harness.setUpAll);
    setUp(() async {
      harness.setUp();
      NewDeviceDismissals.reset();
      await AppSettings.sendTypingNotifications.setItem(false);
    });
    tearDown(() async {
      loadNewDeviceBanner = newDeviceBanner;
      NewDeviceDismissals.reset();
      await harness.tearDown();
      await AppSettings.sendTypingNotifications.setItem(true);
    });

    NewDeviceBannerState state() => const NewDeviceBannerState(
      accountId: '@me:example.org',
      userId: '@alice:example.com',
      deviceIds: ['JLAFKJWSCS'],
    );

    testWidgets('no new device, no banner', (tester) async {
      await harness.open(tester);
      expect(find.byType(NewDeviceBanner), findsNothing);
      await harness.finish(tester);
    });

    testWidgets('Verify opens the encryption screen and changes no trust', (
      tester,
    ) async {
      loadNewDeviceBanner = (room, {required dismissed}) =>
          dismissed.contains(state().dismissKey) ? null : state();
      await harness.open(tester);
      expect(find.byType(NewDeviceBanner), findsOneWidget);
      final keys = harness.client.userDeviceKeys['@alice:example.com']!;
      final before = {
        for (final device in keys.deviceKeys.values)
          device.deviceId: (device.verified, device.blocked, device.signed),
      };
      await tester.tap(find.text('Verify'));
      await harness.settle(tester, rounds: 3);
      expect(
        FluffyChatApp
            .router
            .routerDelegate
            .currentConfiguration
            .last
            .matchedLocation,
        '/rooms/${harness.room.id}/encryption',
      );
      final after = {
        for (final device in keys.deviceKeys.values)
          device.deviceId: (device.verified, device.blocked, device.signed),
      };
      expect(after, before);
      await harness.finish(tester);
    });

    testWidgets('closing hides it for this device set only', (tester) async {
      loadNewDeviceBanner = (room, {required dismissed}) =>
          dismissed.contains(state().dismissKey) ? null : state();
      await harness.open(tester);
      await tester.tap(find.byTooltip('Close').last);
      await harness.settle(tester, rounds: 3);
      expect(find.byType(NewDeviceBanner), findsNothing);
      expect(NewDeviceDismissals.keys, contains(state().dismissKey));
      await harness.finish(tester);
    });
  });
}
