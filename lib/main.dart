// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/app_lock_unavailable/app_lock_unavailable_page.dart';
import 'package:fluffychat/pages/database_key_error/database_key_error_page.dart';
import 'package:fluffychat/utils/app_lock_settings.dart';
import 'package:fluffychat/utils/app_temp_directory.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/font_licenses.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:fluffychat/utils/secure_storage.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/universal_html.dart' as web;

import 'config/setting_keys.dart';
import 'utils/background_push.dart';
import 'widgets/fluffy_chat_app.dart';

ReceivePort? mainIsolateReceivePort;

bool _vodozemacInitialized = false;

bool isIntegrationTest = false;

void main(List<String> args) => runZonedGuarded(() async {
  // Forward Flutter errors to global error reporter
  FlutterError.onError = (details) => Zone.current.handleUncaughtError(
    details.exception,
    details.stack ?? StackTrace.current,
  );

  isIntegrationTest = args.singleOrNull == 'integration_test';
  if (PlatformInfos.isAndroid) {
    final port = mainIsolateReceivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(AppConfig.mainIsolatePortName);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      AppConfig.mainIsolatePortName,
    );
    await waitForPushIsolateDone();
  }

  // Sanitize hash for OIDC:
  if (kIsWeb) {
    final hash = web.window.location.hash;
    if (hash.isNotEmpty && !hash.startsWith('/')) {
      web.window.location.hash = hash.replaceFirst('#', '#?');
    }
  }

  // Our background push shared isolate accesses flutter-internal things very early in the startup proccess
  // To make sure that the parts of flutter needed are started up already, we need to ensure that the
  // widget bindings are initialized already.
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

  final store = await AppSettings.init();
  Logs().i('Welcome to ${AppSettings.applicationName.value} <3');
  await sweepAppTempDirectory();

  kEnableMatrixSdkBenchmarks = AppSettings.benchmarksInLogs.value;

  if (!_vodozemacInitialized) {
    await vod.init(
      wasmPath: './assets/assets/vodozemac/${AppConfig.vodozemacVersion}/',
    );
    _vodozemacInitialized = true;
  }

  Logs().nativeColors = !PlatformInfos.isIOS;

  // If the app starts in detached mode, we assume that it is in
  // background fetch mode for processing push notifications. This is
  // currently only supported on Android.
  if (PlatformInfos.isAndroid &&
      AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState) {
    await ForegroundServices.startService('background_push');

    final List<Client> clients;
    try {
      clients = await ClientManager.getClients(store: store, background: true);
    } on DatabaseKeyUnavailableException catch (e) {
      Logs().w('Database key unavailable in background-fetch mode', e);
      return;
    } on DatabaseOpenFailedException catch (e) {
      Logs().w('Database not openable in background-fetch mode', e);
      return;
    }

    // Do not send online presences when app is in background fetch mode.
    for (final client in clients) {
      client.backgroundSync = false;
      client.syncPresence = backgroundFetchPresence;
    }

    // In the background fetch mode we do not want to waste ressources with
    // starting the Flutter engine but process incoming push notifications.
    BackgroundPush.clientOnly(clients);
    // To start the flutter engine afterwards we add an custom observer.
    WidgetsBinding.instance.addObserver(AppStarter(clients, store));
    Logs().i(
      '${AppSettings.applicationName.value} started in background-fetch mode. No GUI will be created unless the app is no longer detached.',
    );
    return;
  }

  final List<Client> clients;
  try {
    clients = await ClientManager.getClients(store: store);
  } on DatabaseKeyUnavailableException catch (e) {
    Logs().w('Database key unavailable, asking the user', e);
    _showDatabaseErrorPage(store, args, keyProblem: true);
    return;
  } on DatabaseOpenFailedException catch (e) {
    Logs().w('Database not openable, asking the user', e.runtimeType);
    _showDatabaseErrorPage(
      store,
      args,
      keyProblem: false,
      clientName: e.setAsideMayHelp ? e.clientName : null,
    );
    return;
  }

  // Started in foreground mode.
  Logs().i(
    '${AppSettings.applicationName.value} started in foreground mode. Rendering GUI...',
  );
  await startGui(clients, store);
}, ErrorReporter.onFlutterError);

void _showDatabaseErrorPage(
  SharedPreferences store,
  List<String> args, {
  required bool keyProblem,
  String? clientName,
}) => runApp(
  DatabaseKeyErrorPage.app(
    onRetry: () => main(args),
    onReset: () => _resetDatabasesAndRestart(store, args),
    onSetAside: keyProblem || kIsWeb || clientName == null
        ? null
        : () => _setAsideAndRestart(clientName, args),
    resetMayRemovePin: PlatformInfos.isAndroid,
    keyProblem: keyProblem,
  ),
);

Future<bool> _setAsideAndRestart(String clientName, List<String> args) async {
  try {
    await setAccountDatabaseAside(clientName);
  } catch (e) {
    Logs().w('Unable to move the account data aside', e.runtimeType);
    return false;
  }
  main(args);
  return true;
}

Future<bool> _resetDatabasesAndRestart(
  SharedPreferences store,
  List<String> args,
) async {
  final unfinished = await resetLocalDatabases(
    store.getStringList(ClientManager.clientNamespace) ?? [],
  );
  if (unfinished.isNotEmpty) {
    Logs().w('Reset incomplete: ${unfinished.map((step) => step.name)}');
    return false;
  }
  main(args);
  return true;
}

/// Fetch the pincode for the applock and start the flutter engine.
///
/// [readLock] and [show] are replaced by tests.
Future<void> startGui(
  List<Client> clients,
  SharedPreferences store, {
  Future<AppLockRead> Function()? readLock,
  void Function(Widget app) show = runApp,
}) async {
  // Fetch the pin for the applock if existing for mobile applications.
  final lock = await (readLock ?? _readPlatformLock)();
  if (appLockMustBlock(
    lock,
    signedIn: clients.any((client) => client.isLogged()),
  )) {
    show(
      AppLockUnavailablePage.app(
        onRetry: () => startGui(clients, store, readLock: readLock, show: show),
      ),
    );
    return;
  }
  final pin = lock.pincode;
  final useBiometrics = lock.useBiometrics;

  if (PlatformInfos.isLinux || PlatformInfos.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Preload first client
  final firstClient = clients.firstOrNull;
  await firstClient?.roomsLoading;
  await firstClient?.accountDataLoading;

  show(
    FluffyChatApp(
      clients: clients,
      appLockSettings: (pincode: pin, useBiometrics: useBiometrics),
      store: store,
    ),
  );
}

/// Watches the lifecycle changes to start the application when it
/// is no longer detached.
class AppStarter with WidgetsBindingObserver {
  final List<Client> clients;
  final SharedPreferences store;
  bool guiStarted = false;

  AppStarter(this.clients, this.store);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (guiStarted) return;
    if (state == AppLifecycleState.detached) return;

    Logs().i(
      '${AppSettings.applicationName.value} switches from the detached background-fetch mode to ${state.name} mode. Rendering GUI...',
    );
    // Switching to foreground mode needs to reenable send online sync presence.
    for (final client in clients) {
      client.backgroundSync = true;
      client.syncPresence = PresencePolicy.fromSettings().syncPresence(
        foreground: true,
      );
    }
    startGui(clients, store);
    // We must make sure that the GUI is only started once.
    guiStarted = true;
  }
}

Future<AppLockRead> _readPlatformLock() async => PlatformInfos.supportsAppLock
    ? readAppLockSettings(createSecureStorage())
    : (pincode: null, useBiometrics: false, failed: false);
