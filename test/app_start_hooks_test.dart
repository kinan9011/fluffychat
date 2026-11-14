// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/app_start_hooks.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  late Client clientA;
  late Client loggedOut;

  setUpAll(() async {
    clientA = await prepareTestClient(clientName: 'A');
    loggedOut = await prepareTestClient(clientName: 'LoggedOut');
    await loggedOut.logout();
  });

  Client? clientByName(String name) => name == 'A' ? clientA : null;

  CallKitParams call({
    bool accepted = false,
    String roomId = '!r:x',
    String clientName = 'A',
  }) => CallKitParams(
    id: '1',
    isAccepted: accepted,
    extra: {'roomId': roomId, 'clientName': clientName},
  );

  group('hasOtherActiveRtcMember', () {
    MatrixRtcCallMember member(String user, String device) =>
        MatrixRtcCallMember.fromJson({'device_id': device}, senderId: user);

    bool other(List<MatrixRtcCallMember> members) =>
        hasOtherActiveRtcMember(members, userId: '@me:x', deviceId: 'DEV');

    test('only our own membership is a stale entry of this device', () {
      expect(other([member('@me:x', 'DEV')]), isFalse);
    });

    test('the same user on another device counts', () {
      expect(other([member('@me:x', 'OTHER')]), isTrue);
    });

    test('another user counts', () {
      expect(other([member('@you:x', 'DEV')]), isTrue);
    });

    test('nobody in the call', () {
      expect(other([]), isFalse);
    });

    test('our own stale membership does not hide a real participant', () {
      expect(other([member('@me:x', 'DEV'), member('@you:x', 'D2')]), isTrue);
    });
  });

  group('callKitJoinTarget', () {
    test('an accept event for a client that is not logged in is ignored', () {
      expect(
        callKitJoinTarget(call(clientName: 'LoggedOut'), (_) => loggedOut),
        isNull,
      );
    });

    test('an accept event does not need isAccepted', () {
      final target = callKitJoinTarget(call(), clientByName);
      expect(target?.client, clientA);
      expect(target?.roomId, '!r:x');
    });
  });
}
