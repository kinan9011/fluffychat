// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/pages/device_settings/link_device_card.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/devices/device_model.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:material_ui/material_ui.dart';

enum _DeviceAction { rename, verify, block, unblock, signOut }

class DevicesSettingsView extends StatelessWidget {
  final DevicesSettingsController controller;

  const DevicesSettingsView(this.controller, {super.key});

  static IconData iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('android')) return Icons.smartphone_rounded;
    if (['ios', 'iphone', 'ipad'].any(lower.contains)) {
      return Icons.phone_iphone_rounded;
    }
    if (['web', 'firefox', 'chrome', 'safari', 'opera'].any(lower.contains)) {
      return Icons.language_rounded;
    }
    if (['desktop', 'windows', 'macos', 'linux'].any(lower.contains)) {
      return Icons.computer_rounded;
    }
    return Icons.devices_other_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final devices = controller.devices;
    final rows = devices == null
        ? const <DeviceRow>[]
        : controller.rows(l10n.unknownDevice);
    final thisDevice = rows.where((r) => r.isThisDevice).firstOrNull;
    final others = rows.where((r) => !r.isThisDevice).toList();
    return SettingsScaffold(
      title: l10n.linkedDevices,
      children: [
        if (controller.loadError != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
            child: SettingsGroup(
              rows: [
                SettingsRow(
                  key: const ValueKey('devices_retry'),
                  icon: Icons.error_outline_rounded,
                  title: l10n.tryAgain,
                  onTap: controller.reload,
                ),
              ],
            ),
          )
        else if (devices == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        if (devices != null) ...[
          if (controller.chatBackupEnabled == false)
            Container(
              margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.warnS,
                borderRadius: BorderRadius.circular(AppRadius.banner),
              ),
              child: Row(
                spacing: 12,
                children: [
                  Icon(Icons.info_rounded, color: tokens.warn),
                  Expanded(
                    child: Text(
                      l10n.noticeChatBackupDeviceVerification,
                      style: TextStyle(color: tokens.fg, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          if (controller.qrLoginSupported)
            LinkDeviceCard(
              onOpenAccountPage: controller.accountPageUrl == null
                  ? null
                  : controller.openAccountPage,
            ),
          if (thisDevice != null)
            SettingsGroup(
              header: l10n.thisDeviceSection,
              rows: [_DeviceTile(controller: controller, row: thisDevice)],
            ),
          SettingsGroup(
            header: l10n.otherSessions,
            rows: [
              if (others.isEmpty)
                SettingsRow(
                  icon: Icons.devices_rounded,
                  title: l10n.noOtherDevicesFound,
                  showChevron: false,
                  neutralTile: true,
                )
              else
                for (final row in others)
                  _DeviceTile(
                    key: ValueKey('device_${row.deviceId}'),
                    controller: controller,
                    row: row,
                  ),
            ],
          ),
          if (others.isNotEmpty)
            SettingsGroup(
              rows: [
                SettingsRow(
                  key: const ValueKey('sign_out_all_others'),
                  icon: Icons.logout_rounded,
                  title: l10n.signOutAllOthers,
                  destructive: true,
                  showChevron: false,
                  onTap: controller.signOutAllOthersAction,
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.controller, required this.row, super.key});

  final DevicesSettingsController controller;
  final DeviceRow row;

  Future<void> _actions(BuildContext context) async {
    final l10n = L10n.of(context);
    final keys = controller.keysOf(row.deviceId);
    final action = await showModalActionPopup<_DeviceAction>(
      context: context,
      title: row.name,
      cancelLabel: l10n.cancel,
      actions: [
        AdaptiveModalAction(
          value: _DeviceAction.rename,
          icon: const Icon(Icons.edit_outlined),
          label: l10n.changeDeviceName,
        ),
        if (!row.isThisDevice && keys != null) ...[
          if (row.trust != DeviceTrust.verified)
            AdaptiveModalAction(
              value: _DeviceAction.verify,
              icon: const Icon(Icons.verified_outlined),
              label: l10n.verifyStart,
            ),
          if (!keys.blocked)
            AdaptiveModalAction(
              value: _DeviceAction.block,
              icon: const Icon(Icons.block_outlined),
              label: l10n.blockDevice,
              isDestructive: true,
            ),
          if (keys.blocked)
            AdaptiveModalAction(
              value: _DeviceAction.unblock,
              icon: const Icon(Icons.block),
              label: l10n.unblockDevice,
              isDestructive: true,
            ),
        ],
        if (!row.isThisDevice)
          AdaptiveModalAction(
            value: _DeviceAction.signOut,
            icon: const Icon(Icons.logout_rounded),
            label: l10n.signOutSession,
            isDestructive: true,
          ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case _DeviceAction.rename:
        await controller.renameDeviceAction(row.deviceId, row.name);
      case _DeviceAction.verify:
        await controller.verifyDeviceAction(row.deviceId);
      case _DeviceAction.block:
        await controller.blockDeviceAction(row.deviceId);
      case _DeviceAction.unblock:
        await controller.unblockDeviceAction(row.deviceId);
      case _DeviceAction.signOut:
        await controller.signOutSessionAction(row.deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final seen = row.lastSeen;
    final (icon, color, label) = switch (row.trust) {
      DeviceTrust.verified => (
        Icons.verified_user_rounded,
        tokens.ok,
        l10n.verified,
      ),
      DeviceTrust.blocked => (Icons.block_rounded, tokens.red, l10n.blocked),
      DeviceTrust.unverified => (
        Icons.gpp_maybe_rounded,
        tokens.warn,
        l10n.unverified,
      ),
      DeviceTrust.unknown => (
        Icons.help_outline_rounded,
        tokens.mut,
        l10n.unverified,
      ),
    };
    return SettingsRow(
      leading: Container(
        decoration: BoxDecoration(
          color: tokens.surf2,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(
          DevicesSettingsView.iconFor(row.name),
          size: 22,
          color: tokens.fg,
        ),
      ),
      title: row.name,
      subtitle: seen == null
          ? null
          : l10n.lastActiveAgo(seen.localizedTimeShort(context)),
      showChevron: false,
      onTap: () => _actions(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Icon(icon, size: 16, color: color),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
