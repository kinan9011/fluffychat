// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/custom_http_client.dart';
import 'package:fluffychat/utils/custom_image_resizer.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:http/http.dart' show BaseClient;
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'matrix_sdk_extensions/safe_init_client.dart';

abstract class ClientManager {
  static const String clientNamespace = 'im.fluffychat.store.clients';

  static Future<List<Client>> getClients({
    bool initialize = true,
    bool background = false,
    required SharedPreferences store,
    @visibleForTesting Future<Client> Function(String name)? create,
  }) async {
    final clientNames = <String>{};
    try {
      final clientNamesList = store.getStringList(clientNamespace) ?? [];
      clientNames.addAll(clientNamesList);
    } catch (e, s) {
      Logs().w('Client names in store are corrupted', e, s);
      await store.remove(clientNamespace);
    }
    if (clientNames.isEmpty) {
      clientNames.add(PlatformInfos.appDisplayName);
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    final clients = <Client>[];
    try {
      for (final name in clientNames) {
        clients.add(
          await (create?.call(name) ??
              createClient(name, store, background: background)),
        );
      }
      if (initialize) {
        await Future.wait(
          clients.map(
            (client) => client
                .initWithRestore(
                  onMigration: () async {
                    final l10n = await lookupL10n(
                      PlatformDispatcher.instance.locale,
                    );
                    sendInitNotification(
                      l10n.databaseMigrationTitle,
                      l10n.databaseMigrationBody,
                    );
                  },
                )
                .catchError((Object e, StackTrace s) {
                  if (e is DatabaseOpenFailedException ||
                      e is DatabaseKeyUnavailableException) {
                    throw e;
                  }
                  Logs().e('Unable to initialize client', e, s);
                }),
          ),
        );
      }
    } on DatabaseOpenFailedException {
      await _disposeAll(clients);
      rethrow;
    } on DatabaseKeyUnavailableException {
      await _disposeAll(clients);
      rethrow;
    }
    if (initialize) {
      for (final client in clients.where((c) => !c.isLogged())) {
        await store.remove(
          '${ServerCapabilitiesService.callSupportKeyPrefix}${client.clientName}',
        );
      }
    }
    if (clients.length > 1 && clients.any((c) => !c.isLogged())) {
      final loggedOutClients = clients.where((c) => !c.isLogged()).toList();
      for (final client in loggedOutClients) {
        Logs().w(
          'Multi account is enabled but client ${client.userID} is not logged in. Removing...',
        );
        clientNames.remove(client.clientName);
        clients.remove(client);
      }
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    return clients;
  }

  static Future<void> _disposeAll(List<Client> clients) =>
      Future.wait(clients.map((client) => client.dispose().catchError((_) {})));

  static Future<void> addClientNameToStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.add(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static Future<void> removeClientNameFromStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.remove(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static NativeImplementations get nativeImplementations => kIsWeb
      ? NativeImplementationsWebWorker(
          Uri.parse('native_executor.js'),
          timeout: const Duration(minutes: 1),
        )
      : NativeImplementationsIsolate(
          compute,
          vodozemacInit: () => vod.init(
            wasmPath:
                './assets/assets/vodozemac/${AppConfig.vodozemacVersion}/',
          ),
        );

  static Future<Client> createClient(
    String clientName,
    SharedPreferences store, {
    bool background = false,
    @visibleForTesting BaseClient? httpClient,
    @visibleForTesting DatabaseApi? database,
  }) async {
    final shareKeysWith = AppSettings.shareKeysWith.value;
    final enableSoftLogout = AppSettings.enableSoftLogout.value;

    final client = SafeInitClient(
      clientName,
      httpClient: httpClient ?? CustomHttpClient.createHTTPClient(),
      verificationMethods: {
        KeyVerificationMethod.numbers,
        if (kIsWeb || PlatformInfos.isMobile || PlatformInfos.isLinux)
          KeyVerificationMethod.emoji,
      },
      importantStateEvents: <String>{
        // To make room emotes work
        'im.ponies.room_emotes',
        // To display call state in chat list
        MatrixRtcCallMember.eventType,
      },
      customImageResizer: PlatformInfos.supportsCustomImageResizer
          ? customImageResizer
          : null,
      logLevel: Level.verbose,
      database: database ?? await flutterMatrixSdkDatabaseBuilder(clientName),
      supportedLoginTypes: {
        AuthenticationTypes.password,
        AuthenticationTypes.sso,
      },
      nativeImplementations: nativeImplementations,
      defaultNetworkRequestTimeout: const Duration(minutes: 30),
      enableDehydratedDevices: true,
      shareKeysWith:
          ShareKeysWith.values.singleWhereOrNull(
            (share) => share.name == shareKeysWith,
          ) ??
          ShareKeysWith.all,
      onSoftLogout: enableSoftLogout ? (c) => c.refreshAccessToken() : null,
      sendTimelineEventTimeout: Duration(
        seconds: AppSettings.sendTimelineEventTimeout.value,
      ),
    );
    // The first sync goes out inside init(): an unset value would mark a
    // hidden user online before any later PresenceApplier call.
    client.syncPresence = background
        ? backgroundFetchPresence
        : PresencePolicy.fromSettings().syncPresence(foreground: true);
    return client;
  }

  static WindowsInitializationSettings get windowsNotificationSettings =>
      WindowsInitializationSettings(
        appName: AppSettings.applicationName.value,
        appUserModelId: AppConfig.appId,
        guid: AppConfig.windowsNotificationGuid,
      );

  static Future<void> sendInitNotification(String title, String body) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('notifications_icon'),
        iOS: const DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
          defaultActionName: FluffyChatNotificationActions.open.name,
        ),
        windows: windowsNotificationSettings,
        macOS: const DarwinInitializationSettings(),
      ),
    );

    if (kIsWeb &&
        WebFlutterLocalNotificationsPlugin().permissionStatus != .granted) {
      return;
    }

    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'error_message',
          'Error Messages',
          importance: Importance.high,
          priority: Priority.max,
        ),
        iOS: DarwinNotificationDetails(sound: 'notification.caf'),
      ),
    );
  }
}
