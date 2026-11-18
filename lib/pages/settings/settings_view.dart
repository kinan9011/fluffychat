// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/status/status_sheet.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/launch_web_url.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qr_code_viewer.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  static String unreadLabel(int count) => count > 99 ? '99+' : '$count';

  static int unreadCount(Client client) => client.rooms
      .where((room) => room.membership == Membership.join)
      .fold(0, (sum, room) => sum + room.notificationCount);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final accounts = {
      for (final client in matrix.widget.clients)
        if (client.isLogged()) client.userID: client,
    }.values.toList();

    return SettingsScaffold(
      title: l10n.settings,
      largeTitle: true,
      children: [
        _ProfileCard(controller: controller),
        if (accounts.isNotEmpty)
          SettingsGroup(
            header: l10n.settingsAccounts,
            rows: [
              for (final client in accounts)
                _AccountRow(
                  key: ValueKey('settings_account_${client.userID}'),
                  client: client,
                  active: client == matrix.client,
                  onTap: () => matrix.setActiveClient(client),
                ),
              SettingsRow(
                icon: Icons.person_add_alt_1_rounded,
                title: l10n.addAccount,
                onTap: () => context.go('/settings/addaccount'),
              ),
            ],
          ),
        SettingsGroup(
          rows: [
            SettingsRow(
              key: const ValueKey('settings_set_status'),
              icon: Icons.mood_rounded,
              title: l10n.setStatus,
              onTap: () => showStatusSheet(context),
            ),
            SettingsToggleRow(
              icon: Icons.backup_rounded,
              title: l10n.chatBackup,
              value: controller.cryptoIdentityConnected == true,
              onChanged: controller.firstRunBootstrapAction,
            ),
          ],
        ),
        _ManageAccountGroup(),
        SettingsGroup(
          rows: [
            _NavRow(
              icon: Icons.palette_rounded,
              title: l10n.settingsAppearance,
              path: '/settings/appearance',
            ),
            _NavRow(
              icon: Icons.notifications_rounded,
              title: l10n.notifications,
              path: '/settings/notifications',
            ),
            _NavRow(
              icon: Icons.forum_rounded,
              title: l10n.settingsChats,
              path: '/settings/chat',
            ),
            _NavRow(
              icon: Icons.shield_rounded,
              title: l10n.privacyAndSecurity,
              path: '/settings/security',
            ),
            _NavRow(
              icon: Icons.devices_rounded,
              title: l10n.devices,
              path: '/settings/devices',
            ),
            _NavRow(
              icon: Icons.add_reaction_rounded,
              title: l10n.settingsEmotesAndStickers,
              path: '/settings/chat/emotes',
            ),
            _NavRow(
              icon: Icons.storage_rounded,
              title: l10n.settingsDataAndStorage,
              path: '/settings/data',
            ),
            _NavRow(
              icon: Icons.dns_rounded,
              title: l10n.settingsHomeserver,
              path: '/settings/homeserver',
              value: matrix.client.userID?.domain,
            ),
            SettingsRow(
              icon: Icons.privacy_tip_rounded,
              title: l10n.privacy,
              onTap: () => launchWebUrl(AppSettings.privacyPolicy.value),
            ),
            SettingsRow(
              icon: Icons.info_rounded,
              title: l10n.about,
              onTap: () => PlatformInfos.showDialog(context),
            ),
          ],
        ),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.logout_rounded,
              title: l10n.logout,
              destructive: true,
              showChevron: false,
              onTap: controller.logoutAction,
            ),
          ],
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.path,
    this.value,
  });

  final IconData icon;
  final String title;
  final String path;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    return SettingsRow(
      icon: icon,
      title: title,
      value: value,
      onTap: () => context.go(path),
      trailing: activeRoute.startsWith(path)
          ? Icon(Icons.circle, size: 8, color: AppTokens.of(context).acc)
          : null,
    );
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.client,
    required this.active,
    required this.onTap,
    super.key,
  });

  final Client client;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  late final Future<Profile?> _profile = widget.client.fetchOwnProfile();

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final tokens = AppTokens.of(context);
    final unread = SettingsView.unreadCount(client);
    return FutureBuilder<Profile?>(
      future: _profile,
      builder: (context, snapshot) {
        final userId = client.userID ?? '';
        final name = snapshot.data?.displayName ?? userId.localpart ?? userId;
        return SettingsRow(
          leading: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name: name,
            colorSeed: userId,
            size: AppSettingsLayout.tile,
          ),
          title: name,
          subtitle: userId,
          onTap: widget.onTap,
          showChevron: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (unread > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: tokens.acc,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    SettingsView.unreadLabel(unread),
                    style: TextStyle(
                      color: tokens.onacc,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (widget.active)
                Icon(Icons.check_circle_rounded, size: 22, color: tokens.acc),
            ],
          ),
        );
      },
    );
  }
}

class _ManageAccountGroup extends StatefulWidget {
  @override
  State<_ManageAccountGroup> createState() => _ManageAccountGroupState();
}

class _ManageAccountGroupState extends State<_ManageAccountGroup> {
  late final Future<Uri?> _accountManageUrl = Result.capture(
    Matrix.of(context).client.getAuthMetadata(),
  ).then((result) => result.asValue?.value.accountManagementUri);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _accountManageUrl,
    builder: (context, snapshot) {
      final accountManageUrl = snapshot.data;
      if (accountManageUrl == null) return const SizedBox.shrink();
      return SettingsGroup(
        rows: [
          SettingsRow(
            icon: Icons.account_circle_rounded,
            title: L10n.of(context).manageAccount,
            trailing: Icon(
              Icons.open_in_new_rounded,
              size: 20,
              color: AppTokens.of(context).mut,
            ),
            onTap: () => launchWebUrl(
              accountManageUrl.toString(),
              mode: LaunchMode.inAppBrowserView,
            ),
          ),
        ],
      );
    },
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
      child: Material(
        color: tokens.surf,
        borderRadius: BorderRadius.circular(AppSettingsLayout.cardRadius),
        child: FutureBuilder<Profile>(
          future: controller.profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final avatar = profile?.avatarUrl;
            final mxid = Matrix.of(context).client.userID ?? l10n.user;
            final displayname = profile?.displayName ?? mxid.localpart ?? mxid;
            final actions = [
              if (PlatformInfos.isMobile) AvatarAction.camera,
              AvatarAction.file,
              if (avatar != null) AvatarAction.remove,
            ];
            final avatarWidget = Avatar(
              mxContent: avatar,
              name: displayname,
              colorSeed: mxid,
              size: 56,
              animated: true,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  if (profile == null)
                    avatarWidget
                  else
                    PopupMenuButton<AvatarAction>(
                      tooltip: l10n.changeYourAvatar,
                      onSelected: controller.setAvatarAction,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context) => [
                        for (final action in actions)
                          PopupMenuItem(
                            value: action,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 12,
                              children: [
                                Icon(switch (action) {
                                  AvatarAction.camera =>
                                    Icons.camera_alt_outlined,
                                  AvatarAction.file => Icons.photo_outlined,
                                  AvatarAction.remove => Icons.delete_outlined,
                                }),
                                Text(switch (action) {
                                  AvatarAction.camera => l10n.openCamera,
                                  AvatarAction.file => l10n.openGallery,
                                  AvatarAction.remove => l10n.removeYourAvatar,
                                }),
                              ],
                            ),
                          ),
                      ],
                      child: avatarWidget,
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: controller.setDisplaynameAction,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Text(
                              displayname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.fg,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => FluffyShare.share(mxid, context),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Text(
                              mxid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: AppTypography.mono.copyWith(
                                color: tokens.mut,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.myQrCode,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () => showQrCodeViewer(context, mxid),
                    icon: Icon(
                      Icons.qr_code_2_rounded,
                      size: 24,
                      color: tokens.acc,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
