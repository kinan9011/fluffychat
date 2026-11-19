// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/chat/chat.dart';
import 'package:odango/pages/chat/chat_input_row.dart';
import 'package:odango/pages/chat/composer/attachment_type_bar.dart';
import 'package:odango/pages/chat/composer/format_panel.dart';
import 'package:odango/utils/rich_text/format_range.dart';
import 'package:odango/widgets/glass_surface.dart';

import 'utils/chat_page_harness.dart';

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.sendTypingNotifications.setItem(false);
  });
  tearDown(() async {
    await harness.tearDown();
    await AppSettings.sendTypingNotifications.setItem(true);
  });

  testWidgets('composer keeps its keys and swaps mic for send', (tester) async {
    await harness.open(tester);
    expect(find.byKey(const Key('chat_input_field')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatInputRow),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('chat_input_field')), 'hello');
    await harness.settle(tester, rounds: 2);
    expect(find.byKey(const Key('send_button')), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('Aa opens the format panel, the attach button the type bar', (
    tester,
  ) async {
    await harness.open(tester);
    expect(find.byType(FormatPanel), findsNothing);
    expect(find.byType(AttachmentTypeBar), findsNothing);
    await tester.tap(find.byKey(const Key('composer_format_toggle')));
    await harness.settle(tester, rounds: 2);
    expect(find.byType(FormatPanel), findsOneWidget);
    await tester.tap(find.byKey(const Key('composer_attach_button')));
    await harness.settle(tester, rounds: 2);
    expect(find.byType(FormatPanel), findsNothing);
    expect(find.byType(AttachmentTypeBar), findsOneWidget);
    await tester.tap(find.byKey(const Key('composer_attach_button')));
    await harness.settle(tester, rounds: 2);
    expect(find.byType(AttachmentTypeBar), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('the panel fits a landscape screen with the keyboard open', (
    tester,
  ) async {
    await harness.open(tester, width: 640, height: 360);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const Key('composer_format_toggle')));
    await harness.settle(tester, rounds: 3);
    expect(find.byType(FormatPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    final panel = tester.getRect(find.byType(FormatPanel));
    expect(panel.top, greaterThanOrEqualTo(0));
    expect(panel.height, AppChat.formatPanelMinHeight);
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(FormatPanel),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    final field = tester.getRect(find.byKey(const Key('chat_input_field')));
    expect(field.top, greaterThanOrEqualTo(0));
    expect(field.bottom, lessThanOrEqualTo(360 - 200));
    expect(find.byKey(const Key('chat_input_field')).hitTestable(), findsOne);
    await harness.finish(tester);
  });

  testWidgets('the Aa and attach buttons tell screen readers if open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await harness.open(tester);
    const aa = Key('composer_format_toggle');
    const attach = Key('composer_attach_button');
    expect(
      tester.getSemantics(find.byKey(aa)),
      isSemantics(hasSelectedState: true, isSelected: false),
    );
    await tester.tap(find.byKey(aa));
    await harness.settle(tester, rounds: 2);
    expect(
      tester.getSemantics(find.byKey(aa)),
      isSemantics(hasSelectedState: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byKey(attach)),
      isSemantics(hasSelectedState: true, isSelected: false),
    );
    await tester.tap(find.byKey(attach));
    await harness.settle(tester, rounds: 2);
    expect(
      tester.getSemantics(find.byKey(attach)),
      isSemantics(hasSelectedState: true, isSelected: true),
    );
    handle.dispose();
    await harness.finish(tester);
  });

  testWidgets('Ctrl+B, Ctrl+I and Ctrl+U format the selection', (tester) async {
    await harness.open(tester);
    await tester.enterText(find.byKey(const Key('chat_input_field')), 'hello');
    final composer = tester
        .state<ChatController>(find.byType(ChatPageWithRoom))
        .sendController;
    composer.value = composer.value.copyWith(
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    for (final key in [
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyU,
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(composer.format.ranges.map((r) => r.kind).toSet(), {
      RangeKind.bold,
      RangeKind.italic,
      RangeKind.underline,
    });
    await harness.finish(tester);
  });

  testWidgets('on a Mac (also in a browser) Cmd formats, Ctrl does not', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await harness.open(tester);
      await tester.enterText(
        find.byKey(const Key('chat_input_field')),
        'hello',
      );
      final composer = tester
          .state<ChatController>(find.byType(ChatPageWithRoom))
          .sendController;
      composer.value = composer.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(composer.format.ranges, isEmpty);
      composer.value = composer.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(composer.format.ranges.map((r) => r.kind), [RangeKind.bold]);
      await harness.finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the old attach popup menu is gone', (tester) async {
    await harness.open(tester);
    expect(find.byType(PopupMenuButton<AddPopupMenuActions>), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('the emoji picker closes the panels', (tester) async {
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('composer_format_toggle')));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.byIcon(Icons.sticky_note_2_rounded));
    await harness.settle(tester, rounds: 2);
    expect(find.byType(FormatPanel), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('the checklist entry puts a check prefix on the line', (
    tester,
  ) async {
    await harness.open(tester);
    await tester.tap(find.byKey(const Key('composer_attach_button')));
    await harness.settle(tester, rounds: 2);
    await tester.tap(find.byKey(const ValueKey('attach_checklist')));
    await harness.settle(tester, rounds: 2);
    final composer = tester
        .state<ChatController>(find.byType(ChatPageWithRoom))
        .sendController;
    expect(composer.text, '☐ ');
    expect(composer.format.richIntent, isTrue);
    expect(find.byType(FormatPanel), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('no schedule shortcut before W06', (tester) async {
    await harness.open(tester);
    expect(find.byIcon(Icons.schedule_send_rounded), findsNothing);
    expect(find.byIcon(Icons.schedule_send_outlined), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('the action button is a 52 px accent circle', (tester) async {
    await harness.open(tester);
    await tester.enterText(find.byKey(const Key('chat_input_field')), 'x');
    await harness.settle(tester, rounds: 2);
    final size = tester.getSize(find.byKey(const Key('send_button')));
    expect(size, const Size.square(52));
    await harness.finish(tester);
  });

  for (final (brightness, suffix, locale) in [
    (Brightness.light, 'light', const Locale('en')),
    (Brightness.dark, 'dark', const Locale('en')),
  ]) {
    testWidgets('golden $suffix', (tester) async {
      await harness.open(tester, brightness: brightness, locale: locale);
      await expectLater(
        find.byType(ChatInputRow),
        matchesGoldenFile('goldens/chat_composer_$suffix.png'),
      );
      await harness.finish(tester);
    });
  }

  testWidgets('the not-logged-in note sits on a glass pill (REV m16)', (
    tester,
  ) async {
    final room = harness.room;
    final saved = <String, Map<String, DeviceKeys>>{};
    for (final user in room.getParticipants()) {
      final keys = harness.client.userDeviceKeys[user.id];
      if (keys == null || user.id == harness.client.userID) continue;
      saved[user.id] = Map.of(keys.deviceKeys);
      keys.deviceKeys.clear();
    }
    addTearDown(() {
      for (final entry in saved.entries) {
        harness.client.userDeviceKeys[entry.key]!.deviceKeys.addAll(
          entry.value,
        );
      }
    });
    await harness.open(tester);
    final note = find.text(
      'The other party is currently not logged in and therefore cannot '
      'receive messages!',
    );
    expect(note, findsOneWidget);
    expect(
      find.ancestor(of: note, matching: find.byType(GlassSurface)),
      findsOneWidget,
    );
    await harness.finish(tester);
  });
}
