// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/export/export_page.dart';
import 'package:fluffychat/pages/settings_data/settings_data.dart';
import 'package:fluffychat/utils/export/export_model.dart';
import 'package:fluffychat/utils/export/export_runner.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/chat_page_harness.dart';

class _Timeline implements ExportTimeline {
  _Timeline(this.events);

  @override
  final List<Event> events;

  @override
  bool get canLoadMore => false;

  @override
  Future<void> loadMore() async {}

  @override
  Event display(Event event) => event;

  @override
  void dispose() {}
}

class _SpyRunner extends ChatExportRunner {
  _SpyRunner({
    required super.timeline,
    required super.roomId,
    required super.roomName,
    required super.encrypted,
    this.gate,
    this.failWith,
  }) : super(
         texts: const ChatExportTexts(
           undecryptable: '?',
           truncated: 't',
           mediaSkipped: 'm',
         ),
         downloadMedia: _noDownload,
       );

  static Future<Uint8List?> _noDownload(Event _) async => null;

  final Completer<void>? gate;
  final Object? failWith;
  ExportOptions? options;
  ExportCancel? token;

  @override
  Future<ChatExportResult> run(
    ExportOptions options, {
    void Function(int events)? onProgress,
    ExportCancel? cancel,
  }) async {
    this.options = options;
    token = cancel;
    onProgress?.call(3);
    await gate?.future;
    onProgress?.call(4);
    if (cancel?.isCancelled ?? false) throw const ExportCancelled();
    final failure = failWith;
    if (failure != null) throw failure;
    return super.run(options, onProgress: onProgress, cancel: cancel);
  }
}

void main() {
  final harness = ChatPageHarness();
  final saved = <ChatExportResult>[];
  final created = <_SpyRunner>[];
  var saverAnswer = '/chosen/export.html';
  Completer<void>? gate;
  Object? failWith;

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    saved.clear();
    created.clear();
    saverAnswer = '/chosen/export.html';
    gate = null;
    failWith = null;
    ExportController.saverOverride = (context, result) async {
      saved.add(result);
      return saverAnswer.isEmpty ? null : saverAnswer;
    };
    ExportController.runnerOverride = (context, room) async {
      final runner = _SpyRunner(
        timeline: _Timeline([
          Event(
            type: 'm.room.message',
            content: {'msgtype': 'm.text', 'body': 'hello export'},
            room: room,
            eventId: r'$1',
            senderId: '@alice:example.org',
            originServerTs: DateTime.utc(2030, 5, 10, 12),
          ),
        ]),
        roomId: room.id,
        roomName: 'Test room',
        encrypted: room.encrypted,
        gate: gate,
        failWith: failWith,
      );
      created.add(runner);
      return runner;
    };
  });
  tearDown(() async {
    ExportController.saverOverride = null;
    ExportController.runnerOverride = null;
    await harness.tearDown();
  });

  String path() => '/settings/data/export?room=${harness.room.id}';

  Future<void> openPage(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
    String? at,
  }) async {
    await harness.open(
      tester,
      path: at ?? path(),
      width: width,
      height: height,
    );
    await harness.settle(tester, rounds: 4);
  }

  Future<void> tapExport(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('export_button')));
    await harness.settle(tester, rounds: 6);
  }

  void makeEncrypted(bool value) {
    final states = harness.room.states;
    if (value) {
      states[EventTypes.Encryption] = {
        '': StrippedStateEvent(
          type: EventTypes.Encryption,
          content: {'algorithm': 'm.megolm.v1.aes-sha2'},
          senderId: '@alice:example.org',
          stateKey: '',
        ),
      };
    } else {
      states.remove(EventTypes.Encryption);
    }
  }

  testWidgets('the decrypted warning is always shown, media starts off', (
    tester,
  ) async {
    makeEncrypted(false);
    await openPage(tester);
    expect(find.byType(ExportPage), findsOneWidget);
    expect(find.byKey(const ValueKey('export_warning')), findsOneWidget);
    expect(
      find.text(
        'Messages are decrypted on this device. Keep the exported file somewhere safe.',
      ),
      findsOneWidget,
    );
    for (final kind in ExportMediaKind.values) {
      final row = tester.widget<SettingsToggleRow>(
        find.byKey(ValueKey('export_media_${kind.name}')),
      );
      expect(row.value, isFalse);
    }
    await harness.finish(tester);
  });

  testWidgets('an encrypted chat asks first and does nothing on cancel', (
    tester,
  ) async {
    makeEncrypted(true);
    await openPage(tester);
    await tapExport(tester);
    expect(find.text('Export decrypted messages?'), findsOneWidget);
    expect(created, isEmpty, reason: 'nothing is read before the consent');
    await tester.tap(
      find.byKey(const Key('ok_cancel_alert_dialog_cancel_button')),
    );
    await harness.settle(tester, rounds: 4);
    expect(created, isEmpty);
    expect(saved, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('confirming the warning exports and saves the bytes', (
    tester,
  ) async {
    makeEncrypted(true);
    await openPage(tester);
    await tapExport(tester);
    await tester.tap(find.byKey(const Key('ok_cancel_alert_dialog_ok_button')));
    await harness.settle(tester, rounds: 8);
    expect(created, hasLength(1));
    expect(saved, hasLength(1));
    expect(saved.single.fileName, endsWith('.html'));
    expect(String.fromCharCodes(saved.single.bytes), contains('hello export'));
    expect(find.text('Export saved'), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('an unencrypted chat exports without a dialog', (tester) async {
    makeEncrypted(false);
    await openPage(tester);
    await tapExport(tester);
    expect(find.text('Export decrypted messages?'), findsNothing);
    expect(saved, hasLength(1));
    await harness.finish(tester);
  });

  testWidgets('cancelling the save dialog shows no success message', (
    tester,
  ) async {
    makeEncrypted(false);
    saverAnswer = '';
    await openPage(tester);
    await tapExport(tester);
    expect(saved, hasLength(1));
    expect(find.text('Export saved'), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('a failing export says so and saves nothing', (tester) async {
    makeEncrypted(false);
    failWith = const ExportTooLarge();
    await openPage(tester);
    await tapExport(tester);
    expect(find.text('Export failed. Nothing was saved.'), findsOneWidget);
    expect(saved, isEmpty);
    await harness.finish(tester);
  });

  testWidgets('the chosen format and media reach the runner', (tester) async {
    makeEncrypted(false);
    await openPage(tester);
    await tester.tap(find.text('JSON (Matrix events)'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('export_media_files')));
    await tester.pump();
    await tapExport(tester);
    final options = created.single.options!;
    expect(options.format, ExportFormat.json);
    expect(options.media, {ExportMediaKind.files});
    await harness.finish(tester);
  });

  testWidgets('cancel while running saves nothing', (tester) async {
    makeEncrypted(false);
    gate = Completer<void>();
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('export_button')));
    await harness.settle(tester, rounds: 4);
    expect(find.text('Exporting… 3 messages'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export_cancel')));
    await tester.pump();
    gate!.complete();
    await harness.settle(tester, rounds: 6);
    expect(created.single.token!.isCancelled, isTrue);
    expect(saved, isEmpty);
    expect(find.byKey(const ValueKey('export_cancel')), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('leaving the chat during the export stops it', (tester) async {
    makeEncrypted(false);
    gate = Completer<void>();
    await openPage(tester);
    await tester.tap(find.byKey(const ValueKey('export_button')));
    await harness.settle(tester, rounds: 4);
    harness.room.membership = Membership.leave;
    addTearDown(() => harness.room.membership = Membership.join);
    gate!.complete();
    await harness.settle(tester, rounds: 6);
    expect(created.single.token!.isCancelled, isTrue);
    expect(saved, isEmpty);
    harness.room.membership = Membership.join;
    await harness.finish(tester);
  });

  testWidgets('a malformed room parameter goes back to Data and storage', (
    tester,
  ) async {
    await openPage(tester, at: '/settings/data/export?room=not-a-room');
    expect(find.byType(ExportPage), findsNothing);
    expect(find.byType(SettingsData), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a missing room parameter goes back to Data and storage', (
    tester,
  ) async {
    await openPage(tester, at: '/settings/data/export');
    expect(find.byType(SettingsData), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('a room we are not in closes the page', (tester) async {
    await openPage(tester, at: '/settings/data/export?room=!gone:example.com');
    expect(find.byType(ExportPage), findsNothing);
    await harness.finish(tester);
  });

  testWidgets('Data and storage lists the joined chats and opens the export', (
    tester,
  ) async {
    await openPage(tester, at: '/settings/data');
    expect(find.byType(SettingsData), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('export_room_${harness.room.id}')));
    await harness.settle(tester, rounds: 4);
    expect(find.byType(ExportPage), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('320x480 has no overflow', (tester) async {
    makeEncrypted(false);
    await openPage(tester, width: 320, height: 480);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('export_button')), findsOneWidget);
    await harness.finish(tester);
  });
}
