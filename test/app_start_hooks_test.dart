// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/app_start_hooks.dart';
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

  group('acceptedCallToRejoin', () {
    test('a call that is still ringing is ignored', () {
      expect(acceptedCallToRejoin([call()], clientByName), isNull);
    });

    test('an accepted call is joined', () {
      final target = acceptedCallToRejoin([call(accepted: true)], clientByName);
      expect(target?.client, clientA);
      expect(target?.roomId, '!r:x');
    });

    test('the first accepted call wins', () {
      final target = acceptedCallToRejoin([
        call(),
        call(accepted: true, roomId: '!s:x'),
      ], clientByName);
      expect(target?.roomId, '!s:x');
    });

    test('a call of an unknown account is ignored', () {
      expect(
        acceptedCallToRejoin([
          call(accepted: true, clientName: 'B'),
        ], clientByName),
        isNull,
      );
    });

    test('a call of a client that is not logged in is ignored', () {
      expect(loggedOut.isLogged(), isFalse);
      expect(
        acceptedCallToRejoin([
          call(accepted: true, clientName: 'LoggedOut'),
        ], (name) => name == 'LoggedOut' ? loggedOut : null),
        isNull,
      );
    });

    test('a call without extras is ignored', () {
      expect(
        acceptedCallToRejoin([
          CallKitParams(id: '1', isAccepted: true),
        ], clientByName),
        isNull,
      );
      expect(
        acceptedCallToRejoin([
          CallKitParams(id: '1', isAccepted: true, extra: {'roomId': '!r:x'}),
        ], clientByName),
        isNull,
      );
    });

    test('no calls, nothing to join', () {
      expect(acceptedCallToRejoin([], clientByName), isNull);
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
