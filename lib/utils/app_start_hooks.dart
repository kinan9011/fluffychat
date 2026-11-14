// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/platform_infos.dart';
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
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

typedef CallJoinTarget = ({Client client, String roomId});

CallJoinTarget? callKitJoinTarget(
  CallKitParams call,
  Client? Function(String clientName) clientByName,
) {
  final roomId = call.extra?.tryGet<String>('roomId');
  final clientName = call.extra?.tryGet<String>('clientName');
  if (roomId == null || clientName == null) return null;
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

final _posix = p.posix;

/// Files inside the app's private data directory (database, preferences,
/// decrypted media cache) must never be sent to a chat because another app
/// shared a path to them. Only the plugin's own copies directly in the cache
/// directory are allowed.
@visibleForTesting
bool isAllowedSharedPath(
  String path, {
  required String appDataDir,
  required String shareCopyDir,
}) {
  final file = _posix.normalize(path);
  final data = _posix.normalize(appDataDir);
  if (!_posix.equals(file, data) && !_posix.isWithin(data, file)) return true;
  return _posix.equals(_posix.dirname(file), _posix.normalize(shareCopyDir));
}

@visibleForTesting
Future<List<SharedMediaFile>> dropPrivateSharedFiles(
  List<SharedMediaFile> files, {
  required Future<String?> Function(String path) canonicalize,
  required String appDataDir,
  required String shareCopyDir,
}) async {
  final result = <SharedMediaFile>[];
  for (final file in files) {
    if ({SharedMediaType.text, SharedMediaType.url}.contains(file.type)) {
      result.add(file);
      continue;
    }
    final canonical = await canonicalize(file.path.replaceFirst('file://', ''));
    if (canonical == null) continue;
    final allowed = isAllowedSharedPath(
      canonical,
      appDataDir: appDataDir,
      shareCopyDir: shareCopyDir,
    );
    if (!allowed) continue;
    result.add(
      SharedMediaFile(
        path: canonical,
        thumbnail: file.thumbnail,
        duration: file.duration,
        type: file.type,
        mimeType: file.mimeType,
        message: file.message,
      ),
    );
  }
  return result;
}

Future<List<SharedMediaFile>> _filterSharedFiles(
  List<SharedMediaFile> files,
) async {
  if (!PlatformInfos.isAndroid) return files;
  try {
    final appDataDir = await Directory(
      (await getApplicationSupportDirectory()).path,
    ).parent.resolveSymbolicLinks();
    final shareCopyDir = await Directory(
      (await getTemporaryDirectory()).path,
    ).resolveSymbolicLinks();
    return await dropPrivateSharedFiles(
      files,
      canonicalize: (path) async {
        try {
          return await File(path).resolveSymbolicLinks();
        } catch (_) {
          return null;
        }
      },
      appDataDir: appDataDir,
      shareCopyDir: shareCopyDir,
    );
  } catch (e, s) {
    Logs().w('[ShareIntent] unable to check shared files', e, s);
    return [];
  }
}

Future<void> _showSharedMedia(List<SharedMediaFile> sharedFiles) async {
  final files = await _filterSharedFiles(
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
        return FileShareItem(
          XFile(file.path.replaceFirst('file://', ''), mimeType: file.mimeType),
        );
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
