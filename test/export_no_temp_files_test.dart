// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/utils/export/export_model.dart';
import 'package:fluffychat/utils/export/export_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

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

const _canary = 'EXPORT-CANARY-7f3a91';

Set<String> _files(Directory dir) {
  try {
    return dir
        .listSync(recursive: true, followLinks: false)
        .map((e) => e.path)
        .toSet();
  } catch (_) {
    return <String>{};
  }
}

/// Entries that appeared since [before] and hold the canary or are named like
/// an export. Other processes use the temp directory too, so only files that
/// could be ours count.
List<String> _leaks(Directory dir, Set<String> before) {
  final leaks = <String>[];
  for (final path in _files(dir).difference(before)) {
    if (path.toLowerCase().contains('export')) leaks.add(path);
    final file = File(path);
    try {
      if (FileSystemEntity.isFileSync(path) && file.lengthSync() < (4 << 20)) {
        final bytes = file.readAsBytesSync();
        if (String.fromCharCodes(bytes).contains(_canary)) leaks.add(path);
      }
    } catch (_) {}
  }
  return leaks;
}

void main() {
  group('source scan: the export code cannot write a file', () {
    final roots = ['lib/utils/export', 'lib/pages/export'];
    final forbidden = {
      'dart:io': RegExp(r'import\s+.dart:io.'),
      'path_provider': RegExp('path_provider'),
      'dart:html': RegExp(r'dart:html|package:web/'),
      'temporary directory': RegExp('getTemporaryDirectory|systemTemp'),
      'File(': RegExp(r'\bFile\('),
      'Directory(': RegExp(r'\bDirectory\('),
      'writeAsBytes': RegExp('writeAs(Bytes|String)|openWrite'),
      'XFile': RegExp(r'\bXFile\b'),
    };

    test('the folders exist and contain dart files', () {
      for (final root in roots) {
        expect(
          Directory(root).listSync(recursive: true).whereType<File>(),
          isNotEmpty,
          reason: root,
        );
      }
    });

    for (final entry in forbidden.entries) {
      test('no ${entry.key}', () {
        final offenders = <String>[];
        for (final root in roots) {
          for (final file in Directory(root).listSync(recursive: true)) {
            if (file is! File || !file.path.endsWith('.dart')) continue;
            if (entry.value.hasMatch(file.readAsStringSync())) {
              offenders.add(file.path);
            }
          }
        }
        expect(offenders, isEmpty);
      });
    }

    test('the only way out is the system save dialog', () {
      final users = <String>[];
      for (final root in roots) {
        for (final file in Directory(root).listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          if (file.readAsStringSync().contains('FilePicker.saveFile(')) {
            users.add(file.path);
          }
        }
      }
      expect(users, ['lib/utils/export/export_sink.dart']);
    });
  });

  group('running exports leaves nothing behind', () {
    late Client client;
    late Room room;

    setUpAll(() async {
      client = await prepareTestClient();
      room = client.rooms.firstWhere((r) => r.membership == Membership.join);
    });

    Event message(String id, Map<String, Object?> content) => Event(
      type: 'm.room.message',
      content: content,
      room: room,
      eventId: id,
      senderId: '@alice:example.org',
      originServerTs: DateTime.utc(2030, 5, 10, 12),
    );

    ChatExportRunner runner(List<Event> events, {MediaDownloader? download}) =>
        ChatExportRunner(
          timeline: _Timeline(events),
          roomId: room.id,
          roomName: 'Room $_canary',
          encrypted: true,
          texts: const ChatExportTexts(
            undecryptable: '?',
            truncated: 't',
            mediaSkipped: 'm',
          ),
          downloadMedia: download ?? (_) async => Uint8List(8),
        );

    test('html, json, zip, failure and cancel leave no file', () async {
      final temp = Directory.systemTemp;
      final here = Directory.current;
      final tempBefore = _files(temp);
      final hereBefore = _files(here);
      final events = [
        message(r'$1', {'msgtype': 'm.text', 'body': 'hi $_canary'}),
        message(r'$2', {
          'msgtype': 'm.image',
          'body': 'a.png',
          'info': {'size': 8},
        }),
      ];
      const html = ExportOptions(format: ExportFormat.html);
      const withMedia = ExportOptions(
        format: ExportFormat.json,
        media: {ExportMediaKind.photosVideos},
      );
      await runner(events).run(html);
      await runner(events).run(withMedia);
      await runner(
        events,
        download: (_) async => throw Exception('x'),
      ).run(withMedia);
      final cancel = ExportCancel()..isCancelled = true;
      await expectLater(
        runner(events).run(html, cancel: cancel),
        throwsA(isA<ExportCancelled>()),
      );
      expect(_leaks(temp, tempBefore), isEmpty);
      expect(_leaks(here, hereBefore), isEmpty);
    });
  });
}
