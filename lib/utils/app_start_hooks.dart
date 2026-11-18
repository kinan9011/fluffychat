// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/shared_media_filter.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_shortcuts_new/flutter_shortcuts_new.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

typedef CallJoinTarget = ({Client client, String roomId});

bool _isRouteSafeRoomId(String id) =>
    isMatrixRoomId(id) && !id.contains(RegExp(r'[/?#%\\]'));

CallJoinTarget? callKitJoinTarget(
  CallKitParams call,
  Client? Function(String clientName) clientByName,
) {
  final roomId = call.extra?.tryGet<String>('roomId');
  final clientName = call.extra?.tryGet<String>('clientName');
  if (roomId == null || clientName == null || !_isRouteSafeRoomId(roomId)) {
    return null;
  }
  final client = clientByName(clientName);
  if (client == null || !client.isLogged()) return null;
  return (client: client, roomId: roomId);
}

/// A membership of this very device is a leftover of a killed process, not a
/// call that someone else is still in.
@visibleForTesting
bool hasOtherActiveRtcMember(
  Iterable<MatrixRtcCallMember> members, {
  required String? userId,
  required String? deviceId,
}) => members.any((m) => m.senderId != userId || m.deviceId != deviceId);

Future<bool> roomHasOtherActiveCall(Client client, String roomId) async {
  try {
    await client.oneShotSync().timeout(const Duration(seconds: 45));
  } catch (e) {
    Logs().w('[CallKit] no fresh sync for rejoin', e);
    return false;
  }
  final room = client.getRoomById(roomId);
  if (room == null) return false;
  return hasOtherActiveRtcMember(
    room.getActiveMatrixRtcMembers(),
    userId: client.userID,
    deviceId: client.deviceID,
  );
}

Future<void> _endCallKitCall(String id) => FlutterCallkitIncoming.endCall(id);

/// An accepted CallKit entry that survived a process start is only joined if
/// someone else is still in the call, otherwise the mic would open for a call
/// that is long over.
@visibleForTesting
Future<void> rejoinAcceptedCall(
  List<CallKitParams> calls,
  MatrixState matrix, {
  Future<bool> Function(Client client, String roomId) hasActiveCall =
      roomHasOtherActiveCall,
  Future<void> Function(String id) endCall = _endCallKitCall,
}) async {
  for (final call in calls.where((call) => call.isAccepted)) {
    final target = callKitJoinTarget(call, matrix.getClientByName);
    if (target == null) continue;
    if (!await hasActiveCall(target.client, target.roomId)) {
      await endCall(call.id);
      return;
    }
    if (!matrix.mounted) return;
    matrix.joinCall(target.client, target.roomId);
    return;
  }
}

void runAppStartHooks(MatrixState matrix) {
  if (!PlatformInfos.isMobile) return;
  _listenToSharedMedia(matrix);
  _listenToCallKit(matrix);
}

BuildContext? _rootContext() =>
    FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;

void _listenToSharedMedia(MatrixState matrix) {
  unawaited(deleteOldSharedCopies());
  matrix.startupSubscriptions.add(
    ReceiveSharingIntent.instance.getMediaStream().listen((files) async {
      await _showSharedMedia(files);
      ReceiveSharingIntent.instance.reset();
    }, onError: (Object e) => Logs().w('[ShareIntent] stream error', e)),
  );

  ReceiveSharingIntent.instance.getInitialMedia().then((files) async {
    await _showSharedMedia(files);
    ReceiveSharingIntent.instance.reset();
  });

  if (!PlatformInfos.isAndroid) return;
  final shortcuts = FlutterShortcuts();
  shortcuts.initialize().then(
    (_) => shortcuts.listenAction((action) {
      final context = _rootContext();
      if (context == null || !context.mounted) return;
      UrlLauncher(context, action).launchUrl();
    }),
  );
}

Future<void> _showSharedMedia(List<SharedMediaFile> sharedFiles) async {
  final files = await filterSharedFiles(
    sharedFiles
        .where(
          (file) =>
              !file.path.startsWith(AppConfig.deepLinkPrefix) &&
              Uri.tryParse(file.path)?.scheme != 'matrix',
        )
        .toList(),
  );
  if (files.isEmpty) return;
  final context = _rootContext();
  if (context == null || !context.mounted) return;

  showScaffoldDialog(
    context: context,
    builder: (context) => ShareScaffoldDialog(
      items: files.map((file) {
        if ({SharedMediaType.text, SharedMediaType.url}.contains(file.type)) {
          return TextShareItem(file.path);
        }
        return FileShareItem(XFile(file.path, mimeType: file.mimeType));
      }).toList(),
    ),
  );
}

void _listenToCallKit(MatrixState matrix) {
  matrix.startupSubscriptions.add(
    FlutterCallkitIncoming.onEvent.listen(
      (event) => onCallKitEvent(matrix, event),
    ),
  );
  lk.AudioManager.instance.setAudioSessionManagementMode(
    lk.AudioSessionManagementMode.externalCallSystem,
  );
  FlutterCallkitIncoming.activeCalls().then(
    (calls) => rejoinAcceptedCall(calls, matrix),
  );
}

@visibleForTesting
Future<void> onCallKitEvent(MatrixState matrix, CallEvent? event) async {
  switch (event) {
    case CallEventActionCallAccept():
      final target = callKitJoinTarget(
        event.callKitParams,
        matrix.getClientByName,
      );
      if (target != null) matrix.joinCall(target.client, target.roomId);
      break;
    case CallEventActionCallEnded():
      final roomId = event.callKitParams.extra?.tryGet<String>('roomId');
      if (roomId != null && matrix.activeCallRoomId.value == roomId) {
        matrix.activeCallRoomId.value = null;
      }
      break;
    case CallEventActionCallIncoming() || CallEventActionCallStart()
        when PlatformInfos.isIOS:
      // To have audio session correctly configured on iOS:
      lk.AudioManager.instance.setEngineAvailability(.none);
      break;
    case CallEventActionCallToggleAudioSession() when PlatformInfos.isIOS:
      // To have audio session correctly configured on iOS:
      await lk.AudioManager.instance.setEngineAvailability(
        event.isActive ? .defaultAvailability : .none,
      );
      break;
    default:
      break;
  }
}
