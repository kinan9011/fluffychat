// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/crypto_identity.dart' as crypto_identity;
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;

  void updateProfile() {
    setState(() {
      profileUpdated = true;
      profileFuture = null;
    });
    Matrix.of(context).notifyOwnProfileChanged();
  }

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = await profileFuture;
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.editDisplayname,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: profile?.displayName ?? matrix.client.userID!.localpart,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  Future<int> _serverHeldScheduledCount(Client client) async {
    try {
      final store = ScheduledStore.of(client);
      await store.ready;
      return store.serverHeldCount;
    } catch (_) {
      return 0;
    }
  }

  Future<void> logoutAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final held = await _serverHeldScheduledCount(matrix.client);
    if (!mounted) return;
    final consent = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.areYouSureYouWantToLogout,
      message: held == 0
          ? l10n.noBackupWarning
          : '${l10n.noBackupWarning}\n\n${l10n.logoutScheduledWarning(held)}',
      isDestructive: cryptoIdentityConnected == false,
      okLabel: l10n.logout,
      cancelLabel: l10n.cancel,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
    if (!mounted) return;
    context.go('/');
  }

  Future<void> setAvatarAction(AvatarAction action) async {
    final matrix = Matrix.of(context);
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (action == AvatarAction.camera) {
      final result = await ImagePicker().pickImage(source: ImageSource.camera);
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      if (!mounted) return;
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  StreamSubscription<Client>? _activeClientSubscription;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());
    _activeClientSubscription = Matrix.of(context).onActiveClientChanged.listen(
      (_) {
        setState(() {
          profileFuture = null;
          cryptoIdentityConnected = null;
        });
        checkBootstrap();
      },
    );

    super.initState();
  }

  @override
  void dispose() {
    _activeClientSubscription?.cancel();
    super.dispose();
  }

  Future<void> checkBootstrap() async {
    final client = Matrix.of(context).client;
    final connected = await crypto_identity.cryptoIdentityConnected(client);
    if (!mounted || !identical(Matrix.of(context).client, client)) return;
    setState(() => cryptoIdentityConnected = connected);
  }

  bool? cryptoIdentityConnected;

  Future<void> firstRunBootstrapAction([_]) async {
    if (cryptoIdentityConnected == true) {
      final action = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).resetRecoveryKey,
        cancelLabel: L10n.of(context).close,
        isDestructive: true,
      );
      if (action != OkCancelResult.ok) return;
      if (!mounted) return;
      await context.push('/backup?reset=true');
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final userId = client.userID;
    if (userId != null) {
      profileFuture ??= client.getProfileFromUserId(userId);
    }
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
