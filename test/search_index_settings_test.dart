// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/settings_data/search_index_group.dart';
import 'package:odango/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:odango/utils/search/index_feeder.dart';
import 'package:odango/utils/search/indexed_message.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/search_kind.dart';

import 'utils/chat_page_harness.dart';

const _secret = 'SENTINEL-SECRET-BODY';

IndexedMessage _msg(String text) => IndexedMessage(
  roomId: '!a:example.org',
  eventId: r'$e1:example.org',
  senderId: '@alice:example.org',
  timestamp: 1700000000000,
  kind: SearchKind.text,
  text: text,
);

Future<String> _stored(Client client) async => jsonEncode(
  (await client.database.getCustomCacheObject(
    MessageIndex.documentKey,
  ))?.content,
);

void main() {
  final harness = ChatPageHarness();

  setUpAll(harness.setUpAll);
  setUp(() async {
    harness.setUp();
    await AppSettings.store.clear();
    unencryptedClientsThisSession.clear();
    MessageIndex.forget(harness.client);
    await harness.client.database.cacheCustomObject(MessageIndex.documentKey, {
      'v': 1,
      'e': <Object?>[],
    });
  });
  tearDown(harness.tearDown);

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(SearchIndexGroup)));

  Future<MessageIndex> prepare(WidgetTester tester) async {
    final index = MessageIndex.of(harness.client);
    await tester.runAsync(() async {
      await index.ready;
      index.add(_msg(_secret));
      await index.flush();
    });
    return index;
  }

  testWidgets('the row shows how many messages are indexed', (tester) async {
    await prepare(tester);
    await harness.open(tester, path: '/settings/data');
    expect(find.byKey(SearchIndexGroup.rowKey), findsOneWidget);
    expect(find.text(l10n(tester).searchIndexCount(1)), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('without an encrypted database it says: memory only', (
    tester,
  ) async {
    unencryptedClientsThisSession.add('x');
    await harness.open(tester, path: '/settings/data');
    expect(find.text(l10n(tester).searchIndexMemoryOnly), findsOneWidget);
    await harness.finish(tester);
  });

  testWidgets('clearing asks first; cancel changes nothing', (tester) async {
    final index = await prepare(tester);
    await harness.open(tester, path: '/settings/data');
    await tester.tap(find.byKey(SearchIndexGroup.rowKey));
    await harness.settle(tester, rounds: 3);
    expect(find.text(l10n(tester).searchIndexClearConfirm), findsOneWidget);
    await tester.tap(find.text(l10n(tester).cancel));
    await harness.settle(tester, rounds: 3);
    expect(index.length, 1);
    await tester.runAsync(() async {
      expect(await _stored(harness.client), contains(_secret));
    });
    await harness.finish(tester);
  });

  testWidgets('confirming wipes the index and the stored document', (
    tester,
  ) async {
    final index = await prepare(tester);
    await harness.open(tester, path: '/settings/data');
    IndexFeeder.of(harness.client).isCaughtUp = false;
    await tester.tap(find.byKey(SearchIndexGroup.rowKey));
    await harness.settle(tester, rounds: 3);
    expect(IndexFeeder.of(harness.client).isCaughtUp, isFalse);
    await tester.tap(find.text(l10n(tester).searchIndexClear).last);
    await harness.settle(tester, rounds: 3);
    expect(index.length, 0);
    await tester.runAsync(() async {
      expect(await _stored(harness.client), isNot(contains(_secret)));
    });
    expect(find.text(l10n(tester).searchIndexCount(0)), findsOneWidget);
    expect(
      IndexFeeder.of(harness.client).isCaughtUp,
      isTrue,
      reason: 'nothing is read back from the database after a clear',
    );
    await harness.finish(tester);
  });
}
