// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: experimental_member_use

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/app_config.dart';
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

CallJoinTarget? acceptedCallToRejoin(
  Iterable<CallKitParams> calls,
  Client? Function(String clientName) clientByName,
) => calls
    .where((call) => call.isAccepted)
    .map((call) => callKitJoinTarget(call, clientByName))
    .nonNulls
    .firstOrNull;

void runAppStartHooks(MatrixState matrix) {
  if (!PlatformInfos.isMobile) return;
  _listenToSharedMedia(matrix);
  _listenToCallKit(matrix);
}

BuildContext? _rootContext() =>
    FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;

void _listenToSharedMedia(MatrixState matrix) {
  matrix.startupSubscriptions.add(
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      _showSharedMedia(files);
      ReceiveSharingIntent.instance.reset();
    }, onError: (Object e) => Logs().w('[ShareIntent] stream error', e)),
  );

  ReceiveSharingIntent.instance.getInitialMedia().then((files) {
    _showSharedMedia(files);
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

void _showSharedMedia(List<SharedMediaFile> files) {
  files.removeWhere(
    (file) =>
        file.path.startsWith(AppConfig.deepLinkPrefix) ||
        Uri.tryParse(file.path)?.scheme == 'matrix',
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
      (event) => _onCallEvent(matrix, event),
    ),
  );
  lk.AudioManager.instance.setAudioSessionManagementMode(
    lk.AudioSessionManagementMode.externalCallSystem,
  );
  FlutterCallkitIncoming.activeCalls().then((calls) {
    final target = acceptedCallToRejoin(calls, matrix.getClientByName);
    if (target == null) return;
    matrix.joinCall(target.client, target.roomId);
  });
}

Future<void> _onCallEvent(MatrixState matrix, CallEvent? event) async {
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
