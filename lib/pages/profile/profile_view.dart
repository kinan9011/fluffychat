// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/profile/profile_page.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ProfileView extends StatelessWidget {
  final ProfileController controller;

  const ProfileView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final theme = Theme.of(context);
    final client = controller.client;
    final userId = client.userID!;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.profile),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          FutureBuilder<Profile>(
            future: controller.profileFuture,
            builder: (context, snapshot) {
              final displayName =
                  snapshot.data?.displayName ?? userId.localpart ?? userId;
              return Column(
                children: [
                  Avatar(
                    mxContent: snapshot.data?.avatarUrl,
                    name: displayName,
                    colorSeed: userId,
                    size: 96,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Text(
                    displayName,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.huge),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(l10n.matrixId),
                subtitle: Text(userId),
                onTap: controller.copyMatrixId,
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: Text(l10n.myQrCode),
                onTap: controller.showQrCode,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.huge),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.s,
            ),
            child: Text(
              l10n.accounts,
              style: theme.textTheme.labelLarge?.copyWith(color: tokens.acc),
            ),
          ),
          _Group(
            children: [
              for (final account in controller.accounts)
                _AccountTile(
                  key: ObjectKey(account),
                  client: account,
                  selected: account == client,
                  onTap: () => controller.switchAccount(account),
                ),
              ListTile(
                leading: const Icon(Icons.person_add_outlined),
                title: Text(l10n.addAccount),
                onTap: controller.addAccount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.of(context).surf2,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _AccountTile extends StatefulWidget {
  final Client client;
  final bool selected;
  final VoidCallback onTap;

  const _AccountTile({
    required this.client,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  State<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<_AccountTile> {
  late final Future<Profile> _profile = widget.client.fetchOwnProfile();

  @override
  Widget build(BuildContext context) {
    final userId = widget.client.userID!;
    return FutureBuilder<Profile>(
      future: _profile,
      builder: (context, snapshot) {
        final displayName =
            snapshot.data?.displayName ?? userId.localpart ?? userId;
        return ListTile(
          selected: widget.selected,
          leading: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name: displayName,
            colorSeed: userId,
            size: 40,
          ),
          title: Text(displayName, overflow: TextOverflow.ellipsis),
          subtitle: Text(userId, overflow: TextOverflow.ellipsis),
          trailing: widget.selected ? const Icon(Icons.check_rounded) : null,
          onTap: widget.onTap,
        );
      },
    );
  }
}
