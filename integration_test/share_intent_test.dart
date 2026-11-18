// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/shared_media_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Needs an Android device and another app that shares content:// uris. Run
/// `scripts/test_share_intent.sh <device>`, which builds the sender app from
/// `integration_test/share_sender`, starts this test and fires the intents.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shares from another app stay inside the plugin share directory',
    (tester) async {
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        final cache = await getTemporaryDirectory();
        final canaryFiles = File(p.join(support.path, 't197_canary'))
          ..writeAsStringSync('CANARY');
        final canaryPrefs = File(
          p.join(support.parent.path, 'shared_prefs', 't197_canary.xml'),
        )..writeAsStringSync('CANARY');
        final ownFile = File(p.join(cache.path, 't197_own.txt'))
          ..writeAsStringSync('PRIVATE');

        final events = <List<SharedMediaFile>>[];
        final subscription = ReceiveSharingIntent.instance
            .getMediaStream()
            .listen(events.add);
        // ignore: avoid_print
        print('T197_READY');
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (events.length < 6 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        await subscription.cancel();
        addTearDown(() {
          for (final f in [canaryFiles, canaryPrefs, ownFile]) {
            if (f.existsSync()) f.deleteSync();
          }
          final root = Directory(p.join(cache.path, sharedMediaDirName));
          if (root.existsSync()) root.deleteSync(recursive: true);
        });

        expect(events, hasLength(6));
        final root = await sharedMediaRoot();
        expect(root, isNotNull);

        for (final (index, name) in [
          (0, 'holiday photo.txt'),
          (1, 't197_canary'),
          (2, 't197_canary.xml'),
          (3, 't197_abs'),
          (4, 'invoicefdp.exe'),
        ]) {
          final kept = await filterSharedFiles(events[index]);
          expect(events[index], hasLength(1), reason: 'event $index');
          expect(kept, hasLength(1), reason: 'event $index is a plugin copy');
          expect(p.basename(kept.single.path), name);
          expect(p.isWithin(root!, kept.single.path), isTrue);
          expect(File(kept.single.path).readAsStringSync(), 'ATTACKER');
        }

        expect(canaryFiles.readAsStringSync(), 'CANARY');
        expect(canaryPrefs.readAsStringSync(), 'CANARY');
        expect(events[5], isEmpty, reason: 'a provider of this app is refused');
        expect(ownFile.readAsStringSync(), 'PRIVATE');
      });
    },
  );
}
