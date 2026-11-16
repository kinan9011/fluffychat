// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/composer/attachment_type_bar.dart';
import 'package:fluffychat/pages/chat/composer/format_panel.dart';
import 'package:fluffychat/pages/chat/composer/quick_format_bar.dart';
import 'package:fluffychat/pages/chat/composer/rich_text_editing_controller.dart';
import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/golden.dart';

const panelKeys = [
  'bold',
  'italic',
  'underline',
  'strike',
  'code',
  'spoiler',
  'link',
  'heading',
  'quote',
  'bullet',
  'ordered',
  'checklist',
  'codeBlock',
  'maths',
];

RichTextEditingController filled([String text = 'hello world']) {
  final controller = RichTextEditingController()..resetTo(text);
  controller.value = controller.value.copyWith(
    selection: const TextSelection(baseOffset: 6, extentOffset: 11),
  );
  return controller;
}

void main() {
  group('FormatPanel', () {
    testWidgets('is capped by the space the page leaves above the keyboard', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FormatPanel(controller: filled(), availableHeight: 280),
        ),
      );
      final height = tester.getSize(find.byType(FormatPanel)).height;
      expect(height, 280 - AppChat.formatPanelReserve);
    });

    testWidgets('has the 14 controls and undo/redo with labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = filled();
      await pumpGoldenWidget(tester, FormatPanel(controller: controller));
      for (final key in panelKeys) {
        expect(
          find.byKey(ValueKey('format_$key')),
          findsOneWidget,
          reason: key,
        );
      }
      expect(find.byKey(const ValueKey('format_undo')), findsOneWidget);
      expect(find.byKey(const ValueKey('format_redo')), findsOneWidget);
      for (final label in [
        'Bold text',
        'Italic text',
        'Underline',
        'Strikethrough',
        'Inline code',
        'Spoiler',
        'Link',
        'Heading',
        'Quote',
        'Bulleted list',
        'Numbered list',
        'Check list',
        'Code block',
        'Maths',
        'Undo',
        'Redo',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('every control is at least 44 px', (tester) async {
      final controller = filled();
      await pumpGoldenWidget(tester, FormatPanel(controller: controller));
      for (final key in [...panelKeys, 'undo', 'redo']) {
        final size = tester.getSize(find.byKey(ValueKey('format_$key')));
        expect(size.width, greaterThanOrEqualTo(44), reason: key);
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
      }
    });

    testWidgets('bold formats the selection and shows as active', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = filled();
      await pumpGoldenWidget(tester, FormatPanel(controller: controller));
      await tester.tap(find.byKey(const ValueKey('format_bold')));
      await tester.pump();
      expect(controller.format.ranges, [
        const FormatRange(6, 11, RangeKind.bold),
      ]);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('format_bold'))),
        matchesSemantics(
          label: 'Bold text',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('undo stays inert at the start and works after a change', (
      tester,
    ) async {
      final controller = filled();
      await pumpGoldenWidget(tester, FormatPanel(controller: controller));
      await tester.tap(find.byKey(const ValueKey('format_undo')));
      await tester.pump();
      expect(controller.format.ranges, isEmpty);
      await tester.tap(find.byKey(const ValueKey('format_italic')));
      await tester.pump();
      expect(controller.format.ranges, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('format_undo')));
      await tester.pump();
      expect(controller.format.ranges, isEmpty);
      await tester.tap(find.byKey(const ValueKey('format_redo')));
      await tester.pump();
      expect(controller.format.ranges, isNotEmpty);
    });

    testWidgets('block controls add the line prefix and set the intent', (
      tester,
    ) async {
      final controller = RichTextEditingController()..resetTo('item');
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpGoldenWidget(tester, FormatPanel(controller: controller));
      await tester.tap(find.byKey(const ValueKey('format_bullet')));
      await tester.pump();
      expect(controller.text, '- item');
      expect(controller.format.richIntent, isTrue);
      await tester.tap(find.byKey(const ValueKey('format_heading')));
      await tester.pump();
      expect(controller.text, '# item');
    });

    testWidgets('reduce transparency removes the backdrop blur', (
      tester,
    ) async {
      final controller = filled();
      await pumpGoldenWidget(tester, FormatPanel(controller: controller));
      expect(find.byType(BackdropFilter), findsWidgets);
      await AppSettings.reduceTransparency.setItem(true);
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
      await AppSettings.reduceTransparency.setItem(false);
    });

    testWidgets('a short landscape screen and a narrow one do not overflow', (
      tester,
    ) async {
      final controller = filled();
      await pumpGoldenWidget(
        tester,
        FormatPanel(controller: controller),
        size: const Size(320, 360),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is a 7 column grid of two rows at 360 dp', (tester) async {
      await pumpGoldenWidget(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: 336, child: FormatPanel(controller: filled())),
        ),
        size: const Size(360, 640),
      );
      final rows = <double, List<double>>{};
      for (final key in panelKeys) {
        final rect = tester.getRect(find.byKey(ValueKey('format_$key')));
        rows.putIfAbsent(rect.top, () => []).add(rect.left);
        expect(rect.width, greaterThanOrEqualTo(44), reason: key);
      }
      expect(rows.length, 2);
      expect(rows.values.map((row) => row.length), [7, 7]);
      expect(
        rows.values.first.toSet().length,
        7,
        reason: 'seven distinct columns',
      );
      expect(
        rows.values.first.map((x) => x.round()),
        rows.values.last.map((x) => x.round()),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short screen scrolls the grid instead of overflowing', (
      tester,
    ) async {
      await pumpGoldenWidget(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 336,
            child: FormatPanel(controller: filled(), availableHeight: 160),
          ),
        ),
        size: const Size(640, 160),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FormatPanel)).height,
        lessThanOrEqualTo(AppChat.formatPanelMinHeight),
      );
      final last = find.byKey(const ValueKey('format_maths'));
      await tester.dragUntilVisible(
        last,
        find.byType(SingleChildScrollView),
        const Offset(0, -40),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('goldens', (tester) async {
      await expectGoldenVariants(
        tester,
        'format_panel',
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FormatPanel(controller: filled()),
          ),
        ),
        size: const Size(400, 400),
      );
    });
  });

  group('AttachmentTypeBar', () {
    test('entries per platform, in order', () {
      expect(attachmentTypes(mobile: false), [
        AttachmentType.gallery,
        AttachmentType.file,
        AttachmentType.richText,
        AttachmentType.poll,
        AttachmentType.checklist,
      ]);
      expect(attachmentTypes(mobile: true), [
        AttachmentType.gallery,
        AttachmentType.file,
        AttachmentType.richText,
        AttachmentType.poll,
        AttachmentType.checklist,
        AttachmentType.location,
        AttachmentType.photoCamera,
        AttachmentType.videoCamera,
      ]);
    });

    testWidgets('reports the tapped entry and keeps labels', (tester) async {
      final tapped = <AttachmentType>[];
      await pumpGoldenWidget(
        tester,
        AttachmentTypeBar(
          types: attachmentTypes(mobile: false),
          onSelected: tapped.add,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('attach_poll')));
      await tester.tap(find.byKey(const ValueKey('attach_richText')));
      expect(tapped, [AttachmentType.poll, AttachmentType.richText]);
      for (final (name, label) in [
        ('gallery', 'Gallery'),
        ('file', 'File'),
        ('richText', 'Rich text'),
        ('poll', 'Poll'),
        ('checklist', 'Check list'),
      ]) {
        final semantics = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(ValueKey('attach_$name')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(semantics.properties.label, label);
        expect(semantics.properties.button, isTrue);
      }
      expect(tester.getSize(find.byType(AttachmentTypeBar)).height, 66);
    });

    testWidgets('eight entries scroll instead of overflowing', (tester) async {
      await pumpGoldenWidget(
        tester,
        AttachmentTypeBar(
          types: attachmentTypes(mobile: true),
          onSelected: (_) {},
        ),
        size: const Size(320, 300),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(-300, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('attach_videoCamera')), findsOneWidget);
    });

    testWidgets('goldens', (tester) async {
      await expectGoldenVariants(
        tester,
        'attachment_type_bar',
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AttachmentTypeBar(
              types: attachmentTypes(mobile: false),
              onSelected: (_) {},
            ),
          ),
        ),
        size: const Size(400, 120),
      );
    });
  });

  group('QuickFormatBar', () {
    Future<void> pumpBar(
      WidgetTester tester,
      RichTextEditingController controller,
      FocusNode focus,
    ) => pumpGoldenWidget(
      tester,
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          QuickFormatBar(controller: controller, focusNode: focus),
          TextField(controller: controller, focusNode: focus),
        ],
      ),
    );

    testWidgets('shows only for a selection in the focused field', (
      tester,
    ) async {
      final controller = filled();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpBar(tester, controller, focus);
      expect(find.byKey(const ValueKey('quick_bold')), findsNothing);
      focus.requestFocus();
      await tester.pump();
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('quick_bold')), findsOneWidget);
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('quick_bold')), findsNothing);
    });

    testWidgets('has the 8 buttons and formats the selection', (tester) async {
      final controller = filled();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpBar(tester, controller, focus);
      focus.requestFocus();
      await tester.pump();
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      for (final key in [
        'bold',
        'italic',
        'underline',
        'strike',
        'spoiler',
        'code',
        'link',
        'quote',
      ]) {
        expect(find.byKey(ValueKey('quick_$key')), findsOneWidget, reason: key);
        expect(
          tester.getSize(find.byKey(ValueKey('quick_$key'))).height,
          greaterThanOrEqualTo(44),
        );
      }
      await tester.tap(find.byKey(const ValueKey('quick_spoiler')));
      await tester.pump();
      expect(controller.format.ranges, [
        const FormatRange(6, 11, RangeKind.spoiler),
      ]);
      await tester.tap(find.byKey(const ValueKey('quick_quote')));
      await tester.pump();
      expect(controller.text, '> hello world');
    });

    testWidgets('a javascript link is refused, a valid one is stored', (
      tester,
    ) async {
      final controller = filled();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpBar(tester, controller, focus);
      focus.requestFocus();
      await tester.pump();
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick_link')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'javascript:alert(1)',
      );
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid url'), findsOneWidget);
      expect(controller.format.ranges, isEmpty);
      await tester.enterText(find.byType(TextField).last, 'example.org');
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();
      expect(controller.format.ranges.single.kind, RangeKind.link);
      expect(
        controller.format.ranges.single.link,
        Uri.parse('https://example.org'),
      );
    });

    testWidgets('goldens', (tester) async {
      final controller = filled();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      for (final variant in goldenVariants) {
        await pumpGoldenWidget(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QuickFormatBar(controller: controller, focusNode: focus),
                  Focus(focusNode: focus, child: const SizedBox(height: 40)),
                ],
              ),
            ),
          ),
          brightness: variant.brightness,
          rtl: variant.rtl,
          locale: variant.locale,
          size: const Size(400, 200),
        );
        focus.requestFocus();
        controller.value = controller.value.copyWith(
          selection: const TextSelection(baseOffset: 6, extentOffset: 11),
        );
        controller.toggleInline(RangeKind.bold);
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/quick_format_bar_${variant.suffix}.png'),
        );
        controller.toggleInline(RangeKind.bold);
      }
    });
  });
}
