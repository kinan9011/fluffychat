// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/key_backup_banner.dart';
import 'package:fluffychat/utils/account_hooks.dart';
import 'package:fluffychat/utils/app_start_hooks.dart';
import 'package:fluffychat/utils/chat_list/archive_policy.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/draft_migration.dart';
import 'package:fluffychat/utils/draft_store.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/launch_web_url.dart';
import 'package:fluffychat/utils/logout_cleanup.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/utils/spaces/legacy_cache_purge.dart';
import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:fluffychat/utils/uia_request_manager.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/setting_keys.dart';
import '../pages/key_verification/key_verification_dialog.dart';
import '../utils/account_bundles.dart';
import '../utils/background_push.dart';
import '../utils/scheduling/scheduled_queue.dart';
import '../utils/scheduling/scheduled_store.dart';
import '../utils/search/index_feeder.dart';
import '../utils/search/message_index.dart';
import '../utils/server_capabilities/call_support.dart';
import '../utils/server_capabilities/server_capabilities_service.dart';
import 'local_notifications_extension.dart';

class Matrix extends StatefulWidget {
  final Widget? child;

  final List<Client> clients;

  final Map<String, String>? queryParameters;

  final SharedPreferences store;

  const Matrix({
    this.child,
    required this.clients,
    required this.store,
    this.queryParameters,
    super.key,
  });

  @override
  MatrixState createState() => MatrixState();

  /// Returns the (nearest) Client instance of your application.
  static MatrixState of(BuildContext context) =>
      Provider.of<MatrixState>(context, listen: false);
}

class MatrixState extends State<Matrix> {
  Client? _activeClientRef;
  late final ValueNotifier<int> loggedInAccountCount = ValueNotifier(0);
  String? activeBundle;

  SharedPreferences get store => widget.store;

  BackgroundPush? backgroundPush;

  final ValueNotifier<String?> activeCallRoomId = ValueNotifier(null);
  final ValueNotifier<CallPosition> callPosition = ValueNotifier(
    CallPosition.fullScreen,
  );

  Client get client {
    final active = _activeClientRef;
    if (active != null && widget.clients.contains(active)) return active;
    return currentBundle!.first!;
  }

  Client? get activeClientOrNull {
    try {
      return client;
    } catch (_) {
      return null;
    }
  }

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  @visibleForTesting
  static ServerCapabilitySource Function(Client)? capabilitySourceFor;

  late final ServerCapabilitiesService serverCapabilities =
      ServerCapabilitiesService(store: store, sourceFor: capabilitySourceFor);

  final ValueNotifier<int> _activeClientRevision = ValueNotifier(0);

  late final Listenable callsAvailability = Listenable.merge([
    serverCapabilities,
    AppSettings.callsEnabled.listenable,
    _activeClientRevision,
  ]);

  bool callsAvailableFor(Client client) => callsAvailable(
    enabled: AppSettings.callsEnabled.value,
    capabilities: serverCapabilities.cached(client),
  );

  Future<bool> callsAvailableAfterLoad(Client client) async {
    await serverCapabilities.load(client);
    return callsAvailableFor(client);
  }

  final StreamController<Client> _activeClientChanged =
      StreamController.broadcast();
  final StreamController<Client> _accountSwitched =
      StreamController.broadcast();
  final StreamController<Client> _ownProfileChanged =
      StreamController.broadcast();

  Stream<Client> get onActiveClientChanged => _activeClientChanged.stream;

  // Switches that come with a destination (notification, call, `?client=`
  // link) must not reset the tabs, so they have their own stream.
  Stream<Client> get onAccountSwitched => _accountSwitched.stream;

  Stream<Client> get onOwnProfileChanged => _ownProfileChanged.stream;

  void notifyOwnProfileChanged() => _ownProfileChanged.add(client);

  // Pages switch the account while they are built, and listeners must not
  // mark widgets dirty during a build.
  void _bumpActiveClientRevision() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _activeClientRevision.value++;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activeClientRevision.value++;
    });
  }

  void _emitIfChanged(Client? before, {required bool resetTabs}) {
    final after = activeClientOrNull;
    if (after == null || identical(before, after)) return;
    _bumpActiveClientRevision();
    _activeClientChanged.add(after);
    if (resetTabs) _accountSwitched.add(after);
  }

  void setActiveClient(Client? cl, {bool resetTabs = true}) {
    if (cl == null || !widget.clients.contains(cl)) {
      Logs().w('Tried to set an unknown client as active');
      return;
    }
    final before = activeClientOrNull;
    _activeClientRef = cl;
    _emitIfChanged(before, resetTabs: resetTabs);
  }

  static const defaultStartupHooks = runAppStartHooks;

  @visibleForTesting
  static void Function(MatrixState matrix) startupHooks = defaultStartupHooks;

  final List<StreamSubscription> startupSubscriptions = [];
  bool _startupHooksDone = false;

  static const defaultAccountHooks = runAccountHooks;

  @visibleForTesting
  static Future<void> Function(MatrixState, Client, BuildContext) accountHooks =
      defaultAccountHooks;

  BuildContext get _hookContext =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
      context;

  final Set<String> _hookedClients = {};

  Future<void> _migrateDrafts() async {
    try {
      await migrateLegacyDrafts(prefs: store, clients: widget.clients);
    } catch (_) {
      Logs().w('[Drafts] migration failed');
    }
  }

  Future<void> _runAccountHooks(Client client) async {
    if (!_hookedClients.add(client.clientName)) return;
    unawaited(_migrateDrafts());
    unawaited(serverCapabilities.load(client));
    try {
      await accountHooks(this, client, _hookContext);
    } catch (e, s) {
      Logs().w('[AccountHooks] failed', e, s);
    }
  }

  Future<void> _purgeLegacyCaches() async {
    try {
      await purgeLegacySpaceHierarchyCache(store);
    } catch (_) {
      Logs().w('[Spaces] cache purge failed');
    }
  }

  void runStartupHooksOnce() {
    if (_startupHooksDone) return;
    _startupHooksDone = true;
    unawaited(_purgeLegacyCaches());
    startupHooks(this);
    final active = activeClientOrNull;
    if (active != null) unawaited(_runAccountHooks(active));
  }

  /// False when calls are not available: nothing was joined.
  Future<bool> joinCall(Client client, String roomId) async {
    if (!await callsAvailableAfterLoad(client)) return false;
    setActiveClient(client, resetTabs: false);
    FluffyChatApp.router.go('/rooms/$roomId?action=call');
    return true;
  }

  void _updateAccountCount() => loggedInAccountCount.value = widget.clients
      .where((client) => client.isLogged())
      .length;

  void _removeClient(Client c) {
    final before = activeClientOrNull;
    widget.clients.remove(c);
    _hookedClients.remove(c.clientName);
    _updateAccountCount();
    serverCapabilities.forget(c);
    ScheduledQueue.forget(c);
    ScheduledStore.forget(c);
    DraftStore.forget(c);
    IndexFeeder.forget(c);
    MessageIndex.forget(c);
    if (identical(_activeClientRef, c)) _activeClientRef = null;
    _emitIfChanged(before, resetTabs: true);
  }

  List<Client?>? get currentBundle {
    if (!hasComplexBundles) {
      return List.from(widget.clients);
    }
    final bundles = accountBundles;
    if (bundles.containsKey(activeBundle)) {
      return bundles[activeBundle];
    }
    return bundles.values.first;
  }

  Map<String?, List<Client?>> get accountBundles {
    final resBundles =
        <String?, List<({Client? client, AccountBundle? bundle})>>{};
    for (var i = 0; i < widget.clients.length; i++) {
      final bundles = widget.clients[i].accountBundles;
      for (final bundle in bundles) {
        if (bundle.name == null) {
          continue;
        }
        resBundles[bundle.name] ??= [];
        resBundles[bundle.name]!.add((
          client: widget.clients[i],
          bundle: bundle,
        ));
      }
    }
    for (final b in resBundles.values) {
      b.sort(
        (a, b) => a.bundle!.priority == null
            ? 1
            : b.bundle!.priority == null
            ? -1
            : a.bundle!.priority!.compareTo(b.bundle!.priority!),
      );
    }
    return resBundles.map(
      (k, v) => MapEntry(k, v.map((vv) => vv.client).toList()),
    );
  }

  bool get hasComplexBundles => accountBundles.values.any((v) => v.length > 1);

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  @visibleForTesting
  void addLoggedInClient(Client client) {
    if (!widget.clients.contains(client)) widget.clients.add(client);
    ClientManager.addClientNameToStore(client.clientName, store);
    _registerSubs(client.clientName);
    serverCapabilities.load(client, force: true);
    _updateAccountCount();
    _applyPresence();
    setActiveClient(client, resetTabs: false);
    unawaited(_runAccountHooks(client));
  }

  Future<Client> getLoginClient() async {
    if (widget.clients.isNotEmpty && !client.isLogged()) {
      return client;
    }
    final candidate = _loginClientCandidate ??=
        await ClientManager.createClient(
            '${AppSettings.applicationName.value}-${DateTime.now().millisecondsSinceEpoch}',
            store,
          )
          ..onLoginStateChanged.stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) {
                addLoggedInClient(_loginClientCandidate!);
                _loginClientCandidate = null;
                FluffyChatApp.router.go('/backup');
              });
    if (widget.clients.isEmpty) widget.clients.add(candidate);
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onReceipts = <String, StreamSubscription>{};
  final onUnarchiveSub = <String, StreamSubscription<SyncUpdate>>{};
  final onLogoutSub = <String, StreamSubscription<LoginState>>{};

  /// The account of a client as long as it was signed in: a logout clears
  /// `userID` before it tells anyone, and a client can sign in after the app
  /// registered it.
  final _lastUserId = <String, String>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};

  String? _cachedPassword;
  Timer? _cachedPasswordClearTimer;

  String? get cachedPassword => _cachedPassword;

  set cachedPassword(String? p) {
    Logs().d('Password cached');
    _cachedPasswordClearTimer?.cancel();
    _cachedPassword = p;
    _cachedPasswordClearTimer = Timer(const Duration(minutes: 10), () {
      _cachedPassword = null;
      Logs().d('Cached Password cleared');
    });
  }

  String? get activeRoomId {
    final route = FluffyChatApp.router.routeInformationProvider.value.uri.path;
    if (!route.startsWith('/rooms/')) return null;
    return route.split('/')[2];
  }

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: didChangeAppLifecycleState);
    AppSettings.shareOnlineStatus.listenable.addListener(_applyPresence);
    AppSettings.appearOffline.listenable.addListener(_applyPresence);
    AppSettings.presenceAway.listenable.addListener(_applyPresence);
    AppSettings.callsEnabled.listenable.addListener(_endCallWhenDisabled);
    initMatrix();
    _applyPresence();
    _clearDueStatuses();
  }

  void _endCallWhenDisabled() {
    if (!AppSettings.callsEnabled.value) activeCallRoomId.value = null;
  }

  void _clearDueStatuses() {
    final store = StatusClearStore();
    for (final client in widget.clients) {
      unawaited(store.clearIfDue(client, foreground: _foreground));
    }
  }

  bool get _foreground =>
      (_lifecycleState ??
          WidgetsBinding.instance.lifecycleState ??
          AppLifecycleState.resumed) ==
      AppLifecycleState.resumed;

  void _applyPresence() =>
      unawaited(PresenceApplier.apply(widget.clients, foreground: _foreground));

  AppLifecycleListener? _listener;
  AppLifecycleState? _lifecycleState;

  void _registerSubs(String name) {
    final c = getClientByName(name);
    if (c == null) {
      Logs().w(
        'Attempted to register subscriptions for non-existing client $name',
      );
      return;
    }
    onRoomKeyRequestSub[name] ??= c.onRoomKeyRequest.stream.listen((
      RoomKeyRequest request,
    ) async {
      if (widget.clients.any(
        ((cl) =>
            cl.userID == request.requestingDevice.userId &&
            cl.identityKey == request.requestingDevice.curve25519Key),
      )) {
        Logs().i(
          '[Key Request] Request is from one of our own clients, forwarding the key...',
        );
        await request.forwardKey();
      }
    });
    onKeyVerificationRequestSub[name] ??= c.onKeyVerificationRequest.stream
        .listen((KeyVerification request) async {
          var hidPopup = false;
          request.onUpdate = () {
            if (!hidPopup &&
                {
                  KeyVerificationState.done,
                  KeyVerificationState.error,
                }.contains(request.state)) {
              FluffyChatApp.router.pop('dialog');
            }
            hidPopup = true;
          };
          request.onUpdate = null;
          hidPopup = true;
          await KeyVerificationDialog(request: request).show(
            FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
                context,
          );
        });
    unawaited(ScheduledQueue.of(c).start());
    IndexFeeder.of(c)
      ..start()
      ..catchUpAfterFirstSync();
    final knownUserId = c.userID;
    if (knownUserId != null) _lastUserId[name] = knownUserId;
    onLogoutSub[name] ??= c.onLoginStateChanged.stream.listen((state) {
      final userId = c.userID;
      if (userId != null) _lastUserId[name] = userId;
      if (state != LoginState.loggedOut) return;
      final loggedInWithMultipleClients = widget.clients.length > 1;

      unawaited(MessageIndex.of(c).wipe());
      unawaited(
        LogoutCleanup.standard().run(
          clientName: c.clientName,
          userId: _lastUserId.remove(name),
          lastAccount: !loggedInWithMultipleClients,
        ),
      );
      _cancelSubs(c.clientName);
      _removeClient(c);
      ClientManager.removeClientNameFromStore(c.clientName, store);
      InitWithRestoreExtension.deleteSessionBackup(name);

      if (loggedInWithMultipleClients) {
        final snackbarContext =
            FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
            context;

        if (!snackbarContext.mounted) return;
        final l10n = L10n.of(snackbarContext);
        ScaffoldMessenger.of(
          snackbarContext,
        ).showSnackBar(SnackBar(content: Text(l10n.oneClientLoggedOut)));
        return;
      }
      FluffyChatApp.router.go('/');
    });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);
    onUnarchiveSub[name] ??= c.onSync.stream.listen(
      UnarchiveOnMention(c).handle,
    );
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    if (PlatformInfos.isWeb || PlatformInfos.isDesktop) {
      c.onSync.stream.first.then((s) {
        if (kIsWeb) {
          WebFlutterLocalNotificationsPlugin().requestNotificationsPermission();
        }
        onNotification[name] ??= c.onNotification.stream.listen(
          showLocalNotification,
        );
      });
    }
    onReceipts[name] ??= c.onSync.stream.listen(
      (syncUpdate) => cancelNotificationsOnSync(
        syncUpdate,
        c.clientName,
        c.userID!,
        // ignore: use_build_context_synchronously
        L10n.of(context),
        flutterLocalNotificationsPlugin,
      ),
    );
  }

  void _cancelSubs(String name) {
    onRoomKeyRequestSub[name]?.cancel();
    onRoomKeyRequestSub.remove(name);
    onKeyVerificationRequestSub[name]?.cancel();
    onKeyVerificationRequestSub.remove(name);
    onLogoutSub[name]?.cancel();
    onLogoutSub.remove(name);
    onNotification[name]?.cancel();
    onNotification.remove(name);
    onReceipts[name]?.cancel();
    onReceipts.remove(name);
    onUnarchiveSub[name]?.cancel();
    onUnarchiveSub.remove(name);
    KeyBackupBanner.forget(name);
  }

  Future<void> initMatrix() async {
    if (PlatformInfos.isMobile) {
      backgroundPush = BackgroundPush(
        this,
        onFcmError: (errorMsg, {Uri? link}) async {
          final context =
              FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
              this.context;
          if (!context.mounted) return;
          final result = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).pushNotificationsNotAvailable,
            message: errorMsg,
            okLabel: link == null
                ? L10n.of(context).ok
                : L10n.of(context).learnMore,
            cancelLabel: L10n.of(context).doNotShowAgain,
          );
          if (result == OkCancelResult.ok && link != null) {
            launchWebUrl(link.toString(), mode: LaunchMode.externalApplication);
          }
          if (result == OkCancelResult.cancel) {
            await AppSettings.showNoGoogle.setItem(true);
          }
        },
      );
    }
    if (backgroundPush == null) {
      await FlutterLocalNotificationsPlugin().initialize(
        settings: InitializationSettings(
          linux: LinuxInitializationSettings(
            defaultActionName: FluffyChatNotificationActions.open.name,
          ),
          windows: ClientManager.windowsNotificationSettings,
          macOS: const DarwinInitializationSettings(),
          iOS: const DarwinInitializationSettings(),
          android: const AndroidInitializationSettings('notifications_icon'),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: widget.clients,
          router: FluffyChatApp.router,
          l10n: null,
        ),
      );
    }

    for (final c in widget.clients) {
      _registerSubs(c.clientName);
    }
    _updateAccountCount();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasDetached = _lifecycleState == AppLifecycleState.detached;
    _lifecycleState = state;
    if (wasDetached) {
      backgroundPush?.openRoomFromNotification(newActivity: true);
    }
    final foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      _clearDueStatuses();
      final active = activeClientOrNull;
      if (active != null) unawaited(serverCapabilities.load(active));
    }
    for (final client in widget.clients) {
      if (foreground) unawaited(ScheduledQueue.of(client).evaluate());
      if (PlatformInfos.isMobile) {
        client.backgroundSync = foreground;
        client.requestHistoryOnLimitedTimeline = !foreground;
        Logs().v('Set background sync to', foreground);
      }
    }
    _applyPresence();
  }

  @override
  void dispose() {
    _listener?.dispose();
    AppSettings.shareOnlineStatus.listenable.removeListener(_applyPresence);
    AppSettings.appearOffline.listenable.removeListener(_applyPresence);
    AppSettings.presenceAway.listenable.removeListener(_applyPresence);
    AppSettings.callsEnabled.listenable.removeListener(_endCallWhenDisabled);

    for (final sub in onRoomKeyRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onKeyVerificationRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onLogoutSub.values) {
      sub.cancel();
    }
    for (final sub in onNotification.values) {
      sub.cancel();
    }
    for (final sub in onUiaRequest.values) {
      sub.cancel();
    }
    for (final sub in onReceipts.values) {
      sub.cancel();
    }
    for (final sub in onUnarchiveSub.values) {
      sub.cancel();
    }
    for (final sub in startupSubscriptions) {
      sub.cancel();
    }
    onRoomKeyRequestSub.clear();
    onKeyVerificationRequestSub.clear();
    onLogoutSub.clear();
    onNotification.clear();
    onUiaRequest.clear();

    voiceMessageEventId.dispose();
    serverCapabilities.dispose();
    _activeClientRevision.dispose();
    for (final client in widget.clients) {
      ScheduledQueue.forget(client);
      IndexFeeder.forget(client);
    }
    _activeClientChanged.close();
    _accountSwitched.close();
    _ownProfileChanged.close();
    loggedInAccountCount.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(create: (_) => this, child: widget.child);
  }

  Future<void> dehydrateAction(BuildContext context) async {
    final l10n = L10n.of(context);
    final response = await showOkCancelAlertDialog(
      context: context,
      isDestructive: true,
      title: l10n.dehydrate,
      message: l10n.dehydrateWarning,
    );
    if (response != OkCancelResult.ok) {
      return;
    }
    if (!context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: client.exportDump,
    );
    final export = result.result;
    if (export == null) return;

    final exportBytes = Uint8List.fromList(const Utf8Codec().encode(export));

    final exportFileName =
        'fluffychat-export-${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}.fluffybackup';

    final file = MatrixFile(bytes: exportBytes, name: exportFileName);
    if (!context.mounted) return;
    file.save(context);
  }
}

enum CallPosition { fullScreen, top }
