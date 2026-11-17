// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show BaseRequest, StreamedResponse;
import 'package:matrix/matrix.dart';

import 'utils/recording_api.dart';
import 'utils/test_client.dart';

void main() {
  group('PresencePolicy', () {
    test('visible only when sharing and not appearing offline', () {
      for (final share in [true, false]) {
        for (final appear in [true, false]) {
          final policy = PresencePolicy(
            shareOnlineStatus: share,
            appearOffline: appear,
          );
          expect(policy.visibleToOthers, share && !appear);
        }
      }
    });

    test('hidden: sync says offline in the foreground and the background', () {
      const hidden = PresencePolicy(
        shareOnlineStatus: false,
        appearOffline: false,
      );
      const appearOffline = PresencePolicy(
        shareOnlineStatus: true,
        appearOffline: true,
      );
      for (final policy in [hidden, appearOffline]) {
        expect(policy.syncPresence(foreground: true), PresenceType.offline);
        expect(policy.syncPresence(foreground: false), PresenceType.offline);
        expect(policy.statusPresence, PresenceType.offline);
      }
    });

    test(
      'visible: server default in the foreground, away in the background',
      () {
        const visible = PresencePolicy(
          shareOnlineStatus: true,
          appearOffline: false,
        );
        expect(visible.syncPresence(foreground: true), isNull);
        expect(
          visible.syncPresence(foreground: false),
          PresenceType.unavailable,
        );
        expect(visible.statusPresence, PresenceType.online);
      },
    );

    group('Away', () {
      PresencePolicy of({
        required bool share,
        required bool appear,
        required bool away,
      }) => PresencePolicy(
        shareOnlineStatus: share,
        appearOffline: appear,
        away: away,
      );

      test('a hidden user stays offline whatever Away says', () {
        for (final away in [true, false]) {
          for (final (share, appear) in [
            (false, false),
            (true, true),
            (false, true),
          ]) {
            final policy = of(share: share, appear: appear, away: away);
            for (final foreground in [true, false]) {
              expect(
                policy.syncPresence(foreground: foreground),
                PresenceType.offline,
                reason: 'share=$share appear=$appear away=$away',
              );
            }
            expect(policy.statusPresence, PresenceType.offline);
          }
        }
      });

      test('a visible user who is away is unavailable, never online', () {
        final policy = of(share: true, appear: false, away: true);
        expect(policy.syncPresence(foreground: true), PresenceType.unavailable);
        expect(
          policy.syncPresence(foreground: false),
          PresenceType.unavailable,
        );
        expect(policy.statusPresence, PresenceType.unavailable);
      });

      test('a visible user who is not away keeps the old behaviour', () {
        final policy = of(share: true, appear: false, away: false);
        expect(policy.syncPresence(foreground: true), isNull);
        expect(
          policy.syncPresence(foreground: false),
          PresenceType.unavailable,
        );
        expect(policy.statusPresence, PresenceType.online);
      });

      test('away is off by default and read from the settings', () async {
        expect(AppSettings.presenceAway.value, isFalse);
        expect(
          const PresencePolicy(
            shareOnlineStatus: true,
            appearOffline: false,
          ).away,
          isFalse,
        );
      });
    });

    test('the background fetch mode stays offline', () {
      expect(backgroundFetchPresence, PresenceType.offline);
    });
  });

  group('PresenceApplier', () {
    late RecordingApi api;
    late Client client;

    setUp(() async {
      api = RecordingApi();
      client = await prepareTestClient(httpClient: api);
      await AppSettings.store.clear();
      api.clear();
    });

    tearDown(() => client.dispose(closeDatabase: true));

    const hidden = PresencePolicy(
      shareOnlineStatus: false,
      appearOffline: false,
    );
    const visible = PresencePolicy(
      shareOnlineStatus: true,
      appearOffline: false,
    );

    List<RecordedRequest> puts() => api.requests('/presence/', method: 'PUT');

    test(
      'hidden: sync presence offline and one offline PUT, not two',
      () async {
        await PresenceApplier.apply([client], foreground: true, policy: hidden);
        await PresenceApplier.apply([client], foreground: true, policy: hidden);
        await PresenceApplier.apply(
          [client],
          foreground: false,
          policy: hidden,
        );
        expect(client.syncPresence, PresenceType.offline);
        expect(puts(), hasLength(1));
        expect((puts().single.json! as Map)['presence'], 'offline');
      },
    );

    test('visible: no PUT at all', () async {
      await PresenceApplier.apply([client], foreground: true, policy: visible);
      expect(client.syncPresence, isNull);
      expect(puts(), isEmpty);
    });

    test('hidden again after being visible announces again', () async {
      await PresenceApplier.apply([client], foreground: true, policy: hidden);
      await PresenceApplier.apply([client], foreground: true, policy: visible);
      await PresenceApplier.apply([client], foreground: true, policy: hidden);
      expect(puts(), hasLength(2));
    });

    test('a client that logs out between the calls is skipped', () async {
      await client.logout().catchError((_) {});
      api.clear();
      await PresenceApplier.apply([client], foreground: true, policy: hidden);
      expect(puts(), isEmpty);
    });
  });

  group('PresenceApplier failure', () {
    const hidden = PresencePolicy(
      shareOnlineStatus: false,
      appearOffline: false,
    );

    Future<int> puts(_FailingOnce api) async {
      final client = await prepareTestClient(httpClient: api);
      await AppSettings.store.clear();
      api.clear();
      await PresenceApplier.apply([client], foreground: true, policy: hidden);
      await PresenceApplier.apply([client], foreground: true, policy: hidden);
      final count = api.requests('/presence/', method: 'PUT').length;
      await client.dispose(closeDatabase: true);
      return count;
    }

    test('a network failure is retried by the next apply', () async {
      expect(await puts(_FailingOnce(network: true)), 2);
    });

    test('a server that refuses is asked once', () async {
      expect(await puts(_FailingOnce(network: false)), 1);
    });
  });
}

class _FailingOnce extends RecordingApi {
  _FailingOnce({required this.network});

  final bool network;
  var _failed = false;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    final fail =
        !_failed &&
        request.method == 'PUT' &&
        request.url.path.contains('/presence/');
    if (!fail) return super.send(request);
    _failed = true;
    log.add(RecordedRequest(request.method, request.url, ''));
    if (network) throw const SocketException('offline');
    return Future.value(
      StreamedResponse(
        Stream.value(utf8.encode('{"errcode":"M_FORBIDDEN","error":"x"}')),
        403,
      ),
    );
  }
}
