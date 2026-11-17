// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

void main() {
  late RecordingApi api;
  late Client client;
  late DateTime now;
  late StatusClearStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.clear();
    api = RecordingApi();
    client = await prepareTestClient(httpClient: api);
    client.backgroundSync = false;
    now = DateTime(2030, 5, 10, 12);
    store = StatusClearStore(now: () => now);
    api.getOverrides['/status'] = {
      'presence': 'online',
      'status_msg': 'In a meeting',
    };
    api.clear();
  });

  tearDown(() => client.dispose(closeDatabase: true));

  List<RecordedRequest> presenceWrites() =>
      api.requests('/presence/', method: 'PUT');

  const userId = '@test:fakeServer.notExisting';

  test('a due status that the server still shows is cleared once', () async {
    await store.arm(
      userId,
      'In a meeting',
      now.subtract(const Duration(minutes: 1)),
    );
    await store.clearIfDue(client);
    expect(presenceWrites(), hasLength(1));
    final body = presenceWrites().single.json as Map;
    expect(body['status_msg'], '');
    expect(store.recordFor(userId), isNull);
  });

  test('a clear never publishes online for a hidden user', () async {
    await store.arm(
      userId,
      'In a meeting',
      now.subtract(const Duration(minutes: 1)),
    );
    await store.clearIfDue(client);
    expect((presenceWrites().single.json as Map)['presence'], 'offline');
  });

  group('the clear goes through the presence policy', () {
    Future<void> armDue() => store.arm(
      userId,
      'In a meeting',
      now.subtract(const Duration(minutes: 1)),
    );

    String publishedPresence() =>
        (presenceWrites().single.json as Map)['presence'] as String;

    test('visible and in the foreground: online, as the sync would', () async {
      await AppSettings.shareOnlineStatus.setItem(true);
      await armDue();
      await store.clearIfDue(client);
      expect(publishedPresence(), 'online');
    });

    test('visible but not in the foreground: never online', () async {
      await AppSettings.shareOnlineStatus.setItem(true);
      await armDue();
      await store.clearIfDue(client, foreground: false);
      expect(publishedPresence(), 'unavailable');
    });

    test('Away stays away', () async {
      await AppSettings.shareOnlineStatus.setItem(true);
      await AppSettings.presenceAway.setItem(true);
      await armDue();
      await store.clearIfDue(client);
      expect(publishedPresence(), 'unavailable');
    });

    test('hidden wins over everything, in any state', () async {
      await AppSettings.presenceAway.setItem(true);
      await armDue();
      await store.clearIfDue(client, foreground: false);
      expect(publishedPresence(), 'offline');
    });

    test('Appear offline wins over sharing', () async {
      await AppSettings.shareOnlineStatus.setItem(true);
      await AppSettings.appearOffline.setItem(true);
      await armDue();
      await store.clearIfDue(client);
      expect(publishedPresence(), 'offline');
    });

    test('nothing leaves the client before the first sync', () async {
      await AppSettings.shareOnlineStatus.setItem(true);
      await armDue();
      final firstSync = Completer<void>();
      client.firstSyncReceived = firstSync.future;
      final clearing = store.clearIfDue(client);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(api.requests('/presence/'), isEmpty);
      firstSync.complete();
      await clearing;
      expect(presenceWrites(), hasLength(1));
      expect(store.recordFor(userId), isNull);
    });
  });

  test('a newer status set elsewhere is not touched', () async {
    api.getOverrides['/status'] = {
      'presence': 'online',
      'status_msg': 'On holiday',
    };
    await store.arm(
      userId,
      'In a meeting',
      now.subtract(const Duration(minutes: 1)),
    );
    await store.clearIfDue(client);
    expect(presenceWrites(), isEmpty);
    expect(store.recordFor(userId), isNull);
  });

  test('before the deadline nothing happens and the record stays', () async {
    await store.arm(
      userId,
      'In a meeting',
      now.add(const Duration(minutes: 5)),
    );
    await store.clearIfDue(client);
    expect(api.log, isEmpty);
    expect(store.recordFor(userId), isNotNull);
  });

  test('a record that is replaced during the request is kept', () async {
    await store.arm(
      userId,
      'In a meeting',
      now.subtract(const Duration(minutes: 1)),
    );
    api.onRequest = (request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/status')) {
        await store.arm(userId, 'Focusing', now.add(const Duration(hours: 1)));
      }
    };
    await store.clearIfDue(client);
    expect(presenceWrites(), isEmpty);
    expect(store.recordFor(userId)?.message, 'Focusing');
  });

  test('two accounts keep separate records', () async {
    await store.arm(userId, 'A', now.add(const Duration(hours: 1)));
    await store.arm(
      '@other:example.org',
      'B',
      now.add(const Duration(hours: 2)),
    );
    expect(store.read(), hasLength(2));
    await store.disarm(userId);
    expect(store.read().single.userId, '@other:example.org');
  });

  test('a clear for this client never looks at another record', () async {
    await store.arm(
      '@other:example.org',
      'In a meeting',
      now.subtract(const Duration(hours: 1)),
    );
    await store.clearIfDue(client);
    expect(api.log, isEmpty);
    expect(store.recordFor('@other:example.org'), isNotNull);
  });

  group('the stored document is untrusted', () {
    Future<void> put(Object? value) => AppSettings.store.setString(
      StatusClearStore.key,
      value is String ? value : jsonEncode(value),
    );

    test('corrupt json is ignored', () async {
      await put('{not json');
      expect(store.read(), isEmpty);
      await put('"a string"');
      expect(store.read(), isEmpty);
    });

    test('entries of the wrong type or range are dropped', () async {
      final ms = now.millisecondsSinceEpoch;
      await put([
        {'user_id': 1, 'message': 'x', 'clear_at': ms},
        {'user_id': '@a:b', 'message': 5, 'clear_at': ms},
        {'user_id': '@a:b', 'message': 'x', 'clear_at': 'soon'},
        {
          'user_id': '@a:b',
          'message': 'x',
          'clear_at': ms - 400 * 24 * 3600 * 1000,
        },
        {
          'user_id': '@a:b',
          'message': 'x',
          'clear_at': ms + 5 * 365 * 24 * 3600 * 1000,
        },
        {'user_id': '@ok:b', 'message': 'fine', 'clear_at': ms},
        'junk',
        null,
      ]);
      expect(store.read().map((r) => r.userId), ['@ok:b']);
    });

    test('at most 16 records are read', () async {
      final ms = now.millisecondsSinceEpoch;
      await put([
        for (var i = 0; i < 40; i++)
          {'user_id': '@u$i:b', 'message': 'x', 'clear_at': ms},
      ]);
      expect(store.read(), hasLength(StatusClearStore.maxRecords));
    });

    test('an overlong user id or message is dropped', () async {
      final ms = now.millisecondsSinceEpoch;
      await put([
        {'user_id': '@${'a' * 300}:b', 'message': 'x', 'clear_at': ms},
        {'user_id': '@a:b', 'message': 'x' * 5000, 'clear_at': ms},
      ]);
      expect(store.read(), isEmpty);
    });
  });
}
