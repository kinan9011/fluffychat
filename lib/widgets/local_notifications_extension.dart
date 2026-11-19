// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/client_download_content_extension.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/notification_background_handler.dart';
import 'package:odango/utils/platform_infos.dart';
import 'package:odango/utils/push_helper.dart';
import 'package:odango/utils/scheduling/silent_notification.dart';
import 'package:odango/utils/server_capabilities/call_support.dart';
import 'package:odango/widgets/fluffy_chat_app.dart';
import 'package:odango/widgets/incoming_call_dialog.dart';
import 'package:odango/widgets/matrix.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.mp3'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    final callPlan = planCallNotification(
      event,
      callsAvailable: callsAvailableFor(event.room.client),
      canRing: true,
    );
    if (callPlan == CallNotificationPlan.drop) return;
    if (callPlan == CallNotificationPlan.ring) {
      final context =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
          this.context;
      showDialog<bool>(
        context: context,
        builder: (_) => IncomingCallDialog(event: event),
      ).then((accepted) {
        if (accepted != true) return;
        if (!context.mounted) return;
        unawaited(joinCall(event.room.client, event.room.id));
      });
    }

    if (kIsWeb &&
        WebFlutterLocalNotificationsPlugin().permissionStatus != .granted) {
      return;
    }

    final l10n = L10n.of(context);
    final roomId = event.room.id;
    if (activeRoomId == roomId) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title = event.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    final avatarUrl = event.room.avatar;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (kIsWeb && avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );
      } catch (e, s) {
        Logs().d('Unable to pre-download avatar for web notification', e, s);
      }
    }

    final id =
        PlatformInfos.isMacOS || PlatformInfos.isIOS || PlatformInfos.isWeb
        ? '${client.clientName}_${roomId}_${event.eventId}'.hashCode
        : '${client.clientName}_$roomId'.hashCode;

    final unreadRooms = client.rooms.where((r) => r.isUnreadOrInvited).length;

    final silent = notifySilently(
      event,
      highlight: event.room.client.pushruleEvaluator.match(event).highlight,
    );

    if (kIsWeb && AppSettings.webNotificationSound.value && !silent) {
      _audioPlayer.play();
    }

    await FlutterLocalNotificationsPlugin().show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        linux: LinuxNotificationDetails(
          sound: silent ? null : ThemeLinuxSound('message-new-instant'),
          actions: switch (event.type) {
            EventTypes.Message ||
            EventTypes.Encrypted ||
            EventTypes.Sticker => [
              LinuxNotificationAction(
                key: FluffyChatNotificationActions.markAsRead.name,
                label: l10n.markAsRead,
              ),
              LinuxNotificationAction(
                key: FluffyChatNotificationActions.mute.name,
                label: l10n.mute,
              ),
            ],
            RtcNotificationContent.eventType => [
              LinuxNotificationAction(
                key: FluffyChatNotificationActions.enterCall.name,
                label: l10n.enterCall,
              ),
            ],
            _ => [],
          },
        ),
        windows: WindowsNotificationDetails(timestamp: event.originServerTs),
        macOS: DarwinNotificationDetails(
          badgeNumber: unreadRooms,
          presentSound: !silent,
          threadIdentifier: '${client.clientName}_$roomId',
        ),
        web: WebNotificationDetails(
          renotify: true,
          iconUrl: kIsWeb
              ? await avatarUrl?.getThumbnailUri(
                  client,
                  width: size,
                  height: size,
                  method: thumbnailMethod,
                )
              : null,
          timestamp: event.originServerTs,
        ),
      ),
      payload: FluffyChatPushPayload(
        client.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
  }
}
