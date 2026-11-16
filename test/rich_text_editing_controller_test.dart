// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/pages/chat/composer/rich_text_editing_controller.dart';
import 'package:fluffychat/utils/rich_text/editor_text.dart';
import 'package:fluffychat/utils/rich_text/format_range.dart';
import 'package:fluffychat/utils/rich_text/format_state.dart';
import 'package:fluffychat/utils/rich_text/rich_document.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/golden.dart';

void type(RichTextEditingController c, String text) {
  for (final ch in text.characters) {
    final value = c.value;
    final offset = value.selection.isValid
        ? value.selection.end
        : value.text.length;
    final next = value.text.replaceRange(offset, offset, ch);
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + ch.length),
    );
  }
}

void select(RichTextEditingController c, int start, int end) {
  c.value = c.value.copyWith(
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

void main() {
  late RichTextEditingController controller;

  setUp(() => controller = RichTextEditingController());
  tearDown(() => controller.dispose());

  group('format ranges follow the text', () {
    test('bold over a selection survives typing before it', () {
      controller.resetTo('hello world');
      select(controller, 6, 11);
      controller.toggleInline(RangeKind.bold);
      expect(controller.format.ranges, [
        const FormatRange(6, 11, RangeKind.bold),
      ]);
      controller.value = TextEditingValue(
        text: 'Oh hello world',
        selection: const TextSelection.collapsed(offset: 3),
      );
      expect(controller.format.ranges, [
        const FormatRange(9, 14, RangeKind.bold),
      ]);
    });

    test('a pending mark formats what is typed next', () {
      controller.resetTo('');
      controller.toggleInline(RangeKind.italic);
      type(controller, 'ab');
      expect(controller.format.ranges, [
        const FormatRange(0, 2, RangeKind.italic),
      ]);
    });

    test('moving the caret clears the pending mark', () {
      controller.resetTo('abc');
      select(controller, 3, 3);
      controller.toggleInline(RangeKind.bold);
      select(controller, 1, 1);
      type(controller, 'x');
      expect(controller.format.ranges, isEmpty);
    });
  });

  group('edits keep their marks in place', () {
    test('typing a letter equal to its neighbour before a mark', () {
      controller.resetTo(
        'ab',
        state: FormatState(ranges: const [FormatRange(1, 2, RangeKind.bold)]),
      );
      controller.value = const TextEditingValue(
        text: 'abb',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(controller.format.ranges, [
        const FormatRange(2, 3, RangeKind.bold),
      ]);
    });

    test('a block toggle over several lines keeps the marks between them', () {
      controller.resetTo('a\nbcd\ne');
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 2, extentOffset: 5),
      );
      controller.toggleInline(RangeKind.bold);
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      controller.toggleBlock(BlockKind.bullet);
      expect(controller.text, '- a\n- bcd\n- e');
      final bold = controller.format.ranges.single;
      expect(controller.text.substring(bold.start, bold.end), 'bcd');
      controller.undo();
      expect(controller.text, 'a\nbcd\ne');
      expect(
        controller.format.ranges.single,
        const FormatRange(2, 5, RangeKind.bold),
      );
    });
  });

  group('resetTo', () {
    test('replaces text and format atomically and clears undo', () {
      controller.resetTo('abc');
      select(controller, 0, 3);
      controller.toggleInline(RangeKind.bold);
      controller.resetTo('other');
      expect(controller.text, 'other');
      expect(controller.format.isEmpty, isTrue);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
    });

    test('a plain value assignment would keep ranges over unrelated text', () {
      controller.resetTo('abcdef');
      select(controller, 0, 6);
      controller.toggleInline(RangeKind.bold);
      controller.resetTo('');
      type(controller, 'abcdef');
      expect(controller.format.ranges, isEmpty);
    });

    test('state is applied with the text', () {
      controller.resetTo(
        'abc',
        state: FormatState(ranges: const [FormatRange(0, 2, RangeKind.bold)]),
      );
      expect(controller.format.ranges, [
        const FormatRange(0, 2, RangeKind.bold),
      ]);
      expect(controller.draftFormat(), isNotNull);
    });

    test('draftFormat is null without formatting', () {
      controller.resetTo('abc');
      expect(controller.draftFormat(), isNull);
    });
  });

  group('undo and redo', () {
    test('a typing run is one step, a toggle another', () {
      controller.resetTo('');
      type(controller, 'abc');
      select(controller, 0, 3);
      controller.toggleInline(RangeKind.bold);
      expect(controller.format.ranges, isNotEmpty);
      controller.undo();
      expect(controller.format.ranges, isEmpty);
      expect(controller.text, 'abc');
      controller.undo();
      expect(controller.text, '');
      controller.redo();
      expect(controller.text, 'abc');
      controller.redo();
      expect(controller.format.ranges, [
        const FormatRange(0, 3, RangeKind.bold),
      ]);
      expect(controller.canRedo, isFalse);
    });

    test('a new edit clears redo', () {
      controller.resetTo('');
      type(controller, 'a');
      controller.undo();
      expect(controller.canRedo, isTrue);
      type(controller, 'b');
      expect(controller.canRedo, isFalse);
    });

    test('the stack is bounded', () {
      controller.resetTo('');
      for (var i = 0; i < RichLimits.maxUndo + 50; i++) {
        controller.value = TextEditingValue(
          text: 'x' * (i + 1),
          selection: TextSelection.collapsed(offset: i + 1),
        );
        controller.value = TextEditingValue(
          text: 'y' * (i + 1),
          selection: TextSelection.collapsed(offset: i + 1),
        );
      }
      var steps = 0;
      while (controller.canUndo) {
        controller.undo();
        steps++;
      }
      expect(steps, lessThanOrEqualTo(RichLimits.maxUndo));
    });
  });

  group('blocks', () {
    test('heading cycles none, H1, H2, H3, none', () {
      controller.resetTo('title');
      select(controller, 0, 0);
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        controller.toggleBlock(BlockKind.heading);
        seen.add(controller.text);
      }
      expect(seen, ['# title', '## title', '### title', 'title']);
      expect(controller.format.richIntent, isTrue);
    });

    test('quote over two selected lines, and back', () {
      controller.resetTo('a\nb\nc');
      select(controller, 0, 3);
      controller.toggleBlock(BlockKind.quote);
      expect(controller.text, '> a\n> b\nc');
      select(controller, 0, 7);
      controller.toggleBlock(BlockKind.quote);
      expect(controller.text, 'a\nb\nc');
    });

    test('ordered numbers the selected lines', () {
      controller.resetTo('a\nb\nc');
      select(controller, 0, 5);
      controller.toggleBlock(BlockKind.ordered);
      expect(controller.text, '1. a\n2. b\n3. c');
    });

    test('a different block kind replaces the old prefix', () {
      controller.resetTo('- a');
      select(controller, 0, 0);
      controller.toggleBlock(BlockKind.checklist);
      expect(controller.text, '☐ a');
    });

    test('formatting ranges stay with their text when a prefix is added', () {
      controller.resetTo('abc');
      select(controller, 0, 3);
      controller.toggleInline(RangeKind.bold);
      select(controller, 0, 0);
      controller.toggleBlock(BlockKind.bullet);
      expect(controller.text, '- abc');
      expect(controller.format.ranges, [
        const FormatRange(2, 5, RangeKind.bold),
      ]);
    });

    test('code fence wraps the selection and sets the intent', () {
      controller.resetTo('x = 1');
      select(controller, 0, 5);
      controller.insertBlockFence(BlockKind.codeBlock);
      expect(controller.text, '```\nx = 1\n```');
      expect(controller.format.richIntent, isTrue);
    });

    test('a collapsed fence puts the caret inside', () {
      controller.resetTo('');
      controller.insertBlockFence(BlockKind.mathsBlock);
      expect(controller.text, '\$\$\n\n\$\$');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
    });
  });

  group('lists continue on Enter only in rich mode', () {
    void enter(String before, {int? at}) {
      controller.resetTo(before);
      final offset = at ?? before.length;
      controller.format.richIntent = true;
      controller.value = TextEditingValue(
        text: before.replaceRange(offset, offset, '\n'),
        selection: TextSelection.collapsed(offset: offset + 1),
      );
    }

    test('bullet, ordered and checklist continue', () {
      enter('- a');
      expect(controller.text, '- a\n- ');
      enter('1. a');
      expect(controller.text, '1. a\n2. ');
      enter('☐ a');
      expect(controller.text, '☐ a\n☐ ');
      enter('☑ a');
      expect(controller.text, '☑ a\n☐ ');
    });

    test('an empty item leaves the list', () {
      enter('- a\n- ');
      expect(controller.text, '- a\n');
    });

    test('headings, quotes and plain lines do not continue lists', () {
      enter('# a');
      expect(controller.text, '# a\n');
      enter('plain');
      expect(controller.text, 'plain\n');
    });

    test('quote continues', () {
      enter('> a');
      expect(controller.text, '> a\n> ');
    });

    test('inside a fence nothing is added', () {
      enter('```\n- a');
      expect(controller.text, '```\n- a\n');
    });

    test('without rich intent nothing is added', () {
      controller.resetTo('- a');
      controller.value = const TextEditingValue(
        text: '- a\n',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(controller.text, '- a\n');
    });
  });

  group('buildTextSpan', () {
    testWidgets('keeps the plain text of the field for every kind of text', (
      tester,
    ) async {
      final doc = RichDocument([
        const Block(BlockKind.heading, [TextRun('Title')], level: 2),
        Block(BlockKind.paragraph, [
          const TextRun('b', marks: {InlineMark.bold}),
          const TextRun('i', marks: {InlineMark.italic}),
          const TextRun('u', marks: {InlineMark.underline}),
          const TextRun('s', marks: {InlineMark.strike}),
          const TextRun('c', marks: {InlineMark.code}),
          const TextRun('p', marks: {InlineMark.spoiler}),
          TextRun('l', link: Uri.parse('https://example.org')),
          const MathsInline('m'),
        ]),
        const Block(BlockKind.quote, [TextRun('q')]),
        const Block(BlockKind.bullet, [TextRun('b')]),
        const Block(BlockKind.codeBlock, [TextRun('x\ny')], language: 'dart'),
        const Block(BlockKind.mathsBlock, [TextRun('z')]),
      ]);
      final editor = RichEditorText.render(doc);
      controller.resetTo(
        editor.text,
        state: FormatState(ranges: editor.ranges, richIntent: true),
      );
      late TextSpan span;
      await pumpGoldenWidget(
        tester,
        Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 16),
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      );
      expect(span.toPlainText(), controller.text);
    });
  });
}
