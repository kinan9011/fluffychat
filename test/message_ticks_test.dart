// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/message_ticks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

const _me = '@test:fakeServer.notExisting';
const _bob = '@bob:example.org';

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient());

  Room roomWith(Map<String, String> receipts) => Room(
    id: '!r:example.org',
    client: client,
    receiptState: LatestReceiptState(
      global: LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: null,
        latestOwnReceipt: null,
        otherUsers: {
          for (final e in receipts.entries)
            e.key: LatestReceiptStateData(e.value, 1),
        },
      ),
    ),
  );

  Event event(
    Room room,
    String id, {
    String sender = _me,
    EventStatus status = EventStatus.synced,
    String? transactionId,
  }) => Event(
    type: EventTypes.Message,
    content: const {'msgtype': MessageTypes.Text, 'body': 'x'},
    room: room,
    eventId: id,
    senderId: sender,
    originServerTs: DateTime(2030),
    status: status,
    unsigned: transactionId == null ? null : {'transaction_id': transactionId},
  );

  test('nothing in, nothing out', () {
    expect(ownMessageTicks([], _me), isEmpty);
  });

  test('a message nobody read is sent', () {
    final room = roomWith({});
    expect(ownMessageTicks([event(room, r'$1')], _me), {r'$1': Tick.sent});
  });

  test('a receipt on the message itself marks it seen', () {
    final room = roomWith({_bob: r'$1'});
    expect(ownMessageTicks([event(room, r'$1')], _me), {r'$1': Tick.seen});
  });

  test('a receipt on a newer event marks the older own message seen', () {
    final room = roomWith({_bob: r'$2'});
    final ticks = ownMessageTicks([
      event(room, r'$2', sender: _bob),
      event(room, r'$1'),
    ], _me);
    expect(ticks, {r'$1': Tick.seen});
  });

  test('a receipt on an older event does not mark the newer one', () {
    final room = roomWith({_bob: r'$1'});
    final ticks = ownMessageTicks([
      event(room, r'$2'),
      event(room, r'$1'),
    ], _me);
    expect(ticks, {r'$2': Tick.sent, r'$1': Tick.seen});
  });

  test('the own receipt does not count as seen', () {
    final room = Room(
      id: '!r:example.org',
      client: client,
      receiptState: LatestReceiptState(
        global: LatestReceiptStateForTimeline(
          ownPrivate: null,
          ownPublic: null,
          latestOwnReceipt: LatestReceiptStateData(r'$1', 1),
          otherUsers: {},
        ),
      ),
    );
    expect(ownMessageTicks([event(room, r'$1')], _me), {r'$1': Tick.sent});
  });

  test('sending and error are their own states, keyed by transaction id', () {
    final room = roomWith({_bob: r'$9'});
    final ticks = ownMessageTicks([
      event(room, r'$t', status: EventStatus.sending, transactionId: 'txn1'),
      event(room, r'$e', status: EventStatus.error),
    ], _me);
    expect(ticks, {'txn1': Tick.sending, r'$e': Tick.error});
  });

  test('other people messages are not in the map', () {
    final room = roomWith({});
    expect(ownMessageTicks([event(room, r'$1', sender: _bob)], _me), isEmpty);
  });

  test('a message that is still sending never counts its receipts', () {
    final room = roomWith({_bob: r'$s'});
    final ticks = ownMessageTicks([
      event(room, r'$s', status: EventStatus.sending, transactionId: 'txn'),
      event(room, r'$1'),
    ], _me);
    expect(ticks, {'txn': Tick.sending, r'$1': Tick.sent});
  });
}
