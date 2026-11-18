// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_security/default_retention_sheet.dart';
import 'package:fluffychat/pages/settings_security/privacy_toggles.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/beautify_string_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/retention/default_retention.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/database_unencrypted_warning.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SettingsSecurityView extends StatelessWidget {
  final SettingsSecurityController controller;

  const SettingsSecurityView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final publicMasterKey =
        client.userDeviceKeys[client.userID]?.masterKey?.publicKey;
    final retention = matrix.serverCapabilities.cached(
      client,
    )[ServerFeature.retention];
    final retentionSupported = retention == FeatureSupport.supported;
    final retentionNote = switch ((controller.capabilitiesLoaded, retention)) {
      (false, _) || (_, FeatureSupport.supported) => null,
      (_, FeatureSupport.unsupported) => l10n.defaultRetentionUnsupported,
      _ => l10n.defaultRetentionUnknown,
    };
    final crossSigningReady = publicMasterKey != null;
    final lock = AppLock.of(context);

    return SettingsScaffold(
      title: l10n.privacyAndSecurity,
      children: [
        if (isDatabaseUnencrypted)
          const Padding(
            padding: EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
            child: DatabaseUnencryptedWarningTile(),
          ),
        const PrivacyToggles(),
        SettingsGroup(
          rows: [
            AppSettingToggleRow(
              icon: Icons.bug_report_rounded,
              title: l10n.shareCrashReports,
              subtitle: l10n.shareCrashReportsDescription,
              setting: AppSettings.autoSendErrorReports,
              defaultValue: false,
            ),
          ],
        ),
        SettingsGroup(
          header: l10n.sectionMessages,
          rows: [
            ValueListenableBuilder<int>(
              valueListenable: AppSettings.defaultDisappearSeconds.listenable,
              builder: (context, _, _) => SettingsRow(
                key: const ValueKey('default_retention_row'),
                icon: Icons.timer_rounded,
                title: l10n.defaultDisappearTimer,
                subtitle: retentionNote,
                value: defaultRetentionLabel(
                  l10n,
                  DefaultRetention.normalize(
                    AppSettings.defaultDisappearSeconds.value,
                  ),
                ),
                onTap: retentionSupported
                    ? () => showDefaultRetentionSheet(context)
                    : null,
                showChevron: retentionSupported,
              ),
            ),
            SettingsRow(
              icon: Icons.block_rounded,
              title: l10n.blockedUsers,
              value: '${client.ignoredUsers.length}',
              onTap: () => context.go('/settings/security/ignorelist'),
            ),
          ],
        ),
        SettingsGroup(
          header: l10n.sectionEncryption,
          rows: [
            SettingsRow(
              icon: Icons.cloud_done_rounded,
              title: l10n.chatBackup,
              value: switch (controller.cryptoConnected) {
                true => l10n.keyBackupOn,
                false => l10n.keyBackupOff,
                null => null,
              },
              onTap: () => context.push('/backup'),
            ),
            SettingsRow(
              icon: Icons.verified_user_rounded,
              title: l10n.crossSigning,
              value: crossSigningReady
                  ? l10n.crossSigningReady
                  : l10n.crossSigningNotSet,
              showChevron: false,
            ),
            SettingsRow(
              icon: Icons.devices_rounded,
              title: l10n.linkedDevices,
              onTap: () => context.go('/settings/devices'),
            ),
            SettingsRow(
              icon: Icons.key_rounded,
              title: l10n.shareKeysWith,
              subtitle: l10n.shareKeysWithDescription,
              value: client.shareKeysWith.localized(l10n),
              onTap: () => showAdaptiveBottomSheet<void>(
                context: context,
                builder: (_) => _ShareKeysSheet(controller: controller),
              ),
            ),
            if (publicMasterKey != null)
              _KeyRow(
                icon: Icons.verified_user_outlined,
                title: l10n.yourPublicKey,
                value: publicMasterKey.beautified,
              ),
            _KeyRow(
              icon: Icons.mobile_friendly_rounded,
              title: l10n.deviceIdentityKey,
              value: client.fingerprintKey.beautified,
            ),
          ],
        ),
        if (PlatformInfos.supportsAppLock)
          SettingsGroup(
            header: l10n.appLock,
            footer: l10n.appLockDescription,
            rows: [
              SettingsToggleRow(
                icon: Icons.lock_rounded,
                title: l10n.useAppLock,
                value: lock.isActive,
                onChanged: (active) => active
                    ? controller.setAppLockAction()
                    : controller.disableAppLockAction(),
              ),
              if (lock.isActive) ...[
                FutureBuilder(
                  future: LocalAuthentication().canCheckBiometrics,
                  builder: (context, snapshot) {
                    if (snapshot.data != true) return const SizedBox.shrink();
                    return SettingsToggleRow(
                      icon: Icons.fingerprint_rounded,
                      title: l10n.unlockWithBiometrics,
                      value: lock.useBiometrics,
                      onChanged: (_) => controller.toggleBiometrics(),
                    );
                  },
                ),
                SettingsRow(
                  icon: Icons.lock_reset_rounded,
                  title: l10n.resetPin,
                  onTap: controller.setAppLockAction,
                ),
              ],
            ],
          ),
        SettingsGroup(
          header: l10n.account,
          rows: [
            _ChangePasswordRow(),
            SettingsRow(
              icon: Icons.delete_sweep_rounded,
              title: l10n.dehydrate,
              showChevron: false,
              onTap: controller.dehydrateAction,
            ),
            SettingsRow(
              icon: Icons.delete_rounded,
              title: l10n.deleteAccount,
              destructive: true,
              showChevron: false,
              onTap: controller.deleteAccountAction,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChangePasswordRow extends StatefulWidget {
  @override
  State<_ChangePasswordRow> createState() => _ChangePasswordRowState();
}

class _ChangePasswordRowState extends State<_ChangePasswordRow> {
  late final Future<Capabilities> _capabilities = Matrix.of(
    context,
  ).client.getCapabilities().timeout(const Duration(seconds: 10));

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _capabilities,
    builder: (context, snapshot) {
      final enabled = snapshot.data?.mChangePassword?.enabled;
      if (enabled == false) return const SizedBox.shrink();
      if (snapshot.data == null && snapshot.error == null) {
        return const SizedBox.shrink();
      }
      return SettingsRow(
        icon: Icons.password_rounded,
        title: L10n.of(context).changePassword,
        onTap: () => context.go('/settings/security/password'),
      );
    },
  );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSettingsLayout.rowPadding,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsIconTile(icon, neutral: true),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SelectableText(
                  value,
                  textDirection: TextDirection.ltr,
                  style: AppTypography.mono.copyWith(
                    color: tokens.mut,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareKeysSheet extends StatefulWidget {
  const _ShareKeysSheet({required this.controller});

  final SettingsSecurityController controller;

  @override
  State<_ShareKeysSheet> createState() => _ShareKeysSheetState();
}

class _ShareKeysSheetState extends State<_ShareKeysSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final current = Matrix.of(context).client.shareKeysWith;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSettingsLayout.sideMargin),
        child: SettingsGroup(
          header: l10n.shareKeysWith,
          footer: l10n.shareKeysWithDescription,
          rows: [
            for (final share in ShareKeysWith.values)
              SettingsRow(
                title: share.localized(l10n),
                showChevron: false,
                trailing: share == current
                    ? Icon(Icons.check_rounded, color: tokens.acc)
                    : null,
                onTap: () async {
                  await widget.controller.changeShareKeysWith(share);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }
}

extension on ShareKeysWith {
  String localized(L10n l10n) {
    switch (this) {
      case ShareKeysWith.all:
        return l10n.allDevices;
      case ShareKeysWith.crossVerifiedIfEnabled:
        return l10n.crossVerifiedDevicesIfEnabled;
      case ShareKeysWith.crossVerified:
        return l10n.crossVerifiedDevices;
      case ShareKeysWith.directlyVerifiedOnly:
        return l10n.verifiedDevicesOnly;
    }
  }
}
