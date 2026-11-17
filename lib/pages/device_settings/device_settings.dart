// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:async/async.dart' show Result;
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/device_settings/device_settings_view.dart';
import 'package:fluffychat/pages/key_verification/key_verification_dialog.dart';
import 'package:fluffychat/utils/devices/device_model.dart';
import 'package:fluffychat/utils/launch_web_url.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' hide Result;

class DevicesSettings extends StatefulWidget {
  const DevicesSettings({super.key});

  @override
  DevicesSettingsController createState() => DevicesSettingsController();
}

class DevicesSettingsController extends State<DevicesSettings> {
  List<Device>? devices;
  Object? loadError;
  bool? chatBackupEnabled;
  bool qrLoginSupported = false;
  Uri? accountPageUrl;

  late Client _client;

  Client get client => Matrix.of(context).client;

  bool get _sameClient => mounted && identical(client, _client);

  @override
  void initState() {
    super.initState();
    _client = client;
    unawaited(reload());
    unawaited(_checkChatBackup());
    unawaited(_loadServerFacts());
  }

  Future<void> reload() async {
    final asked = _client;
    if (mounted) setState(() => loadError = null);
    try {
      final result = await asked.getDevices();
      if (!_sameClient || !identical(asked, _client)) return;
      setState(() => devices = result ?? const []);
    } catch (e) {
      if (!_sameClient) return;
      setState(() {
        loadError = e;
        devices = null;
      });
    }
  }

  Future<void> _checkChatBackup() async {
    final asked = _client;
    final state = await asked.getCryptoIdentityState();
    if (!_sameClient || !identical(asked, _client)) return;
    setState(() => chatBackupEnabled = state.initialized && !state.connected);
  }

  Future<void> _loadServerFacts() async {
    final asked = _client;
    final matrix = Matrix.of(context);
    final caps = await matrix.serverCapabilities.load(asked);
    final metadata = await Result.capture(asked.getAuthMetadata());
    if (!_sameClient || !identical(asked, _client)) return;
    setState(() {
      qrLoginSupported = caps.supports(ServerFeature.qrLogin);
      accountPageUrl = metadata.asValue?.value.accountManagementUri;
    });
  }

  String? get ownDeviceId => _client.deviceID;

  Map<String, DeviceTrust> get trust {
    final keys = _client.userDeviceKeys[_client.userID]?.deviceKeys;
    return {
      for (final entry in (keys ?? const <String, DeviceKeys>{}).entries)
        entry.key: deviceTrust(
          hasKeys: true,
          blocked: entry.value.blocked,
          verified: entry.value.verified,
        ),
    };
  }

  List<DeviceRow> rows(String unnamed) => buildDeviceRows(
    devices ?? const [],
    ownDeviceId,
    trust: trust,
    unnamed: unnamed,
  );

  DeviceKeys? keysOf(String deviceId) =>
      _client.userDeviceKeys[_client.userID]?.deviceKeys[deviceId];

  int get otherCount => otherDeviceIds(devices ?? const [], ownDeviceId).length;

  Future<Uri?> _accountManagementUri() async {
    final cached = accountPageUrl;
    if (cached != null) return cached;
    final wellKnown = await Result.capture(client.getWellknown());
    final url = wellKnown.asValue?.value.additionalProperties
        .tryGetMap<String, Object?>('org.matrix.msc2965.authentication')
        ?.tryGet<String>('account');
    return url == null ? null : Uri.tryParse(url);
  }

  void openAccountPage() {
    final url = accountPageUrl;
    if (url == null) return;
    launchWebUrl(url.toString(), mode: LaunchMode.inAppBrowserView);
  }

  /// [only] null means every other session of the fresh server list.
  Future<void> _deleteOthers({List<String>? only}) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final asked = _client;
    final result = await showFutureLoadingDialog<int>(
      context: context,
      delay: false,
      future: () async {
        final fresh = await asked.getDevices() ?? const <Device>[];
        final allowed = otherDeviceIds(fresh, asked.deviceID);
        final ids = only == null
            ? allowed
            : [
                for (final id in only)
                  if (allowed.contains(id)) id,
              ];
        if (ids.isEmpty) return 0;
        await asked.uiaRequestBackground(
          (auth) => asked.deleteDevices(ids, auth: auth),
        );
        return ids.length;
      },
    );
    if (!mounted) return;
    await reload();
    if (!mounted || result.error != null) return;
    final count = result.result ?? 0;
    if (count > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.signedOutSessions(count))),
      );
    }
  }

  Future<void> signOutAllOthersAction() async {
    final l10n = L10n.of(context);
    final count = otherCount;
    if (count == 0 || ownDeviceId == null) return;
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.signOutAllOthersTitle,
      message: l10n.signOutAllOthersBody(count),
      okLabel: l10n.signOutAllOthers,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok || !mounted) return;
    final managed = await _accountManagementUri();
    if (!mounted) return;
    if (managed != null) {
      launchWebUrl(managed.toString(), mode: LaunchMode.inAppBrowserView);
      return;
    }
    await _deleteOthers();
  }

  Future<void> signOutSessionAction(String deviceId) async {
    final l10n = L10n.of(context);
    if (deviceId == ownDeviceId) return;
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.signOutSessionTitle,
      message: l10n.signOutAllOthersBody(1),
      okLabel: l10n.signOutSession,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok || !mounted) return;
    final managed = await _accountManagementUri();
    if (!mounted) return;
    if (managed != null) {
      launchWebUrl(managed.toString(), mode: LaunchMode.inAppBrowserView);
      return;
    }
    await _deleteOthers(only: [deviceId]);
  }

  Future<void> renameDeviceAction(String deviceId, String? current) async {
    final l10n = L10n.of(context);
    final asked = _client;
    final displayName = await showTextInputDialog(
      context: context,
      title: l10n.changeDeviceName,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: current,
    );
    if (displayName == null || !mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => asked.updateDevice(deviceId, displayName: displayName),
    );
    if (success.error == null && mounted) await reload();
  }

  Future<void> verifyDeviceAction(String deviceId) async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.verifyOtherDevice,
      message: l10n.verifyOtherDeviceDescription,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
    );
    if (consent != OkCancelResult.ok || !mounted) return;
    final keys = keysOf(deviceId);
    if (keys == null) return;
    final req = await keys.startVerification();
    req.onUpdate = () {
      if ({
        KeyVerificationState.error,
        KeyVerificationState.done,
      }.contains(req.state)) {
        if (mounted) setState(() {});
      }
    };
    if (!mounted) return;
    await KeyVerificationDialog(request: req).show(context);
  }

  Future<void> blockDeviceAction(String deviceId) async {
    final key = keysOf(deviceId);
    if (key == null) return;
    if (key.directVerified) await key.setVerified(false);
    await key.setBlocked(true);
    if (mounted) setState(() {});
  }

  Future<void> unblockDeviceAction(String deviceId) async {
    final key = keysOf(deviceId);
    if (key == null) return;
    await key.setBlocked(false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => DevicesSettingsView(this);
}
