// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/export/export_model.dart';
import 'package:fluffychat/utils/export/export_sink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakePicker extends FilePickerPlatform {
  final calls = <String>[];
  Uri? answer = Uri.parse('file:///chosen/export.json');
  Object? saveError;
  Object? clearError;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls.add('save');
    final error = saveError;
    if (error != null) throw error;
    return answer;
  }

  @override
  Future<void> clearTemporaryFiles() async {
    calls.add('clear');
    final error = clearError;
    if (error != null) throw error;
  }
}

final _result = ChatExportResult(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: 'export.json',
  mimeType: 'application/json',
  eventCount: 1,
  skippedMedia: 0,
  truncated: false,
);

void main() {
  late _FakePicker picker;
  late FilePickerPlatform original;

  setUp(() {
    original = FilePickerPlatform.instance;
    picker = _FakePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    FilePickerPlatform.instance = original;
  });

  Future<String?> save(
    WidgetTester tester, [
    TargetPlatform platform = TargetPlatform.iOS,
  ]) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = platform;
    try {
      return await saveExport(context, _result);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('on iOS the plugin stages the bytes in tmp: cleared afterwards', () {
    testWidgets('saved: the staging is cleared after the save', (tester) async {
      expect(await save(tester), 'file:///chosen/export.json');
      expect(picker.calls, ['save', 'clear']);
    });

    testWidgets('cancelled (null): the staging is cleared', (tester) async {
      picker.answer = null;
      expect(await save(tester), isNull);
      expect(picker.calls, ['save', 'clear']);
    });

    testWidgets('the save throws: cleared, and the error still arrives', (
      tester,
    ) async {
      picker.saveError = StateError('disk');
      await expectLater(() => save(tester), throwsStateError);
      expect(picker.calls, ['save', 'clear']);
    });

    testWidgets('a failing clear does not hide the result of the save', (
      tester,
    ) async {
      picker.clearError = StateError('tmp');
      expect(await save(tester), 'file:///chosen/export.json');
      expect(picker.calls, ['save', 'clear']);
    });
  });

  group('other platforms write to the chosen place only', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      testWidgets('$platform does not touch the temporary files', (
        tester,
      ) async {
        await save(tester, platform);
        expect(picker.calls, ['save']);
      });
    }
  });
}
