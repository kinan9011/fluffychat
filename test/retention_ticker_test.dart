// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:fluffychat/utils/retention/retention_ticker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;
  const policy = RetentionPolicy(Duration(hours: 1));

  setUpAll(() async {
    client = await prepareTestClient();
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));

  Event expiringIn(Duration wait) => Event(
    type: EventTypes.Message,
    content: {'msgtype': 'm.text', 'body': 'hi'},
    room: room,
    eventId: r'$a:example.org',
    senderId: '@bob:example.org',
    originServerTs: DateTime.now().add(wait).subtract(policy.maxLifetime),
  );

  Future<void> pause(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('fires when the next message expires', () async {
    var fired = 0;
    final ticker = RetentionTicker(
      onExpire: () => fired++,
      minWait: const Duration(milliseconds: 10),
    );
    ticker.schedule(policy, [expiringIn(const Duration(milliseconds: 80))]);
    await pause(30);
    expect(fired, 0);
    await pause(150);
    expect(fired, 1);
    ticker.dispose();
  });

  test('never waits less than the minimum, so it cannot spin', () async {
    var fired = 0;
    final ticker = RetentionTicker(
      onExpire: () => fired++,
      minWait: const Duration(milliseconds: 120),
    );
    ticker.schedule(policy, [expiringIn(const Duration(milliseconds: 5))]);
    await pause(60);
    expect(fired, 0);
    await pause(200);
    expect(fired, 1);
    ticker.dispose();
  });

  test('no policy or nothing to expire arms nothing', () async {
    var fired = 0;
    final ticker = RetentionTicker(
      onExpire: () => fired++,
      minWait: const Duration(milliseconds: 10),
    );
    ticker.schedule(null, [expiringIn(const Duration(milliseconds: 30))]);
    ticker.schedule(policy, const []);
    await pause(120);
    expect(fired, 0);
    ticker.dispose();
  });

  test('scheduling again replaces the timer', () async {
    var fired = 0;
    final ticker = RetentionTicker(
      onExpire: () => fired++,
      minWait: const Duration(milliseconds: 10),
    );
    ticker.schedule(policy, [expiringIn(const Duration(milliseconds: 40))]);
    ticker.schedule(null, const []);
    await pause(150);
    expect(fired, 0);
    ticker.dispose();
  });

  test('dispose cancels it', () async {
    var fired = 0;
    final ticker = RetentionTicker(
      onExpire: () => fired++,
      minWait: const Duration(milliseconds: 10),
    );
    ticker.schedule(policy, [expiringIn(const Duration(milliseconds: 40))]);
    ticker.dispose();
    await pause(150);
    expect(fired, 0);
  });
}
