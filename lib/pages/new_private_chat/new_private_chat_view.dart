// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/new_message/contact_list.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class NewPrivateChatView extends StatelessWidget {
  final NewPrivateChatController controller;

  const NewPrivateChatView(this.controller, {super.key});

  static const fieldKey = ValueKey('new_message_field');
  static const listKey = ValueKey('new_message_list');
  static const cancelKey = ValueKey('new_message_cancel');
  static const newGroupKey = ValueKey('new_message_group');
  static const newSpaceKey = ValueKey('new_message_space');
  static const scanKey = ValueKey('new_message_scan');
  static const inviteKey = ValueKey('new_message_invite');

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final searchResponse = controller.searchResponse;
    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSettingsLayout.maxWidth,
            ),
            child: ListView(
              key: listKey,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsetsDirectional.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 8,
                    top: 4,
                    end: 8,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: cancelKey,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 48),
                              foregroundColor: tokens.acc,
                            ),
                            onPressed: () => context.canPop()
                                ? context.pop()
                                : context.go('/rooms'),
                            child: Text(
                              l10n.cancel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l10n.newMessage,
                            textAlign: TextAlign.center,
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
                      const SizedBox(width: 88),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 16,
                    end: 16,
                    bottom: 14,
                  ),
                  child: TextField(
                    key: fieldKey,
                    controller: controller.controller,
                    focusNode: controller.textFieldFocus,
                    onChanged: controller.searchUsers,
                    style: TextStyle(color: tokens.fg, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: l10n.newMessageSearchHint,
                      hintStyle: TextStyle(color: tokens.mut),
                      filled: true,
                      fillColor: tokens.surf2,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 21,
                        color: tokens.mut,
                      ),
                      suffixIcon: controller.controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: l10n.clear,
                              icon: Icon(
                                Icons.cancel_rounded,
                                size: 19,
                                color: tokens.mut,
                              ),
                              onPressed: () {
                                controller.controller.clear();
                                controller.searchUsers();
                              },
                            ),
                    ),
                  ),
                ),
                if (searchResponse == null)
                  _Start(controller)
                else
                  _DirectoryResults(
                    controller: controller,
                    future: searchResponse,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Start extends StatelessWidget {
  final NewPrivateChatController controller;

  const _Start(this.controller);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final contacts = controller.contacts;
    final actions = [
      (
        NewPrivateChatView.newGroupKey,
        Icons.group_add_outlined,
        l10n.newGroup,
        () => context.go('/rooms/newgroup'),
      ),
      (
        NewPrivateChatView.newSpaceKey,
        Icons.workspaces_outlined,
        l10n.newSpace,
        () => context.go('/rooms/newspace'),
      ),
      if (PlatformInfos.isMobile)
        (
          NewPrivateChatView.scanKey,
          Icons.qr_code_scanner_rounded,
          l10n.scanQrCode,
          controller.openScannerAction,
        ),
      (
        NewPrivateChatView.inviteKey,
        Icons.link_rounded,
        l10n.newMessageShareLink,
        controller.inviteAction,
      ),
    ];
    return Column(
      children: [
        Container(
          margin: const EdgeInsetsDirectional.only(
            start: 16,
            end: 16,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: tokens.surf,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              for (final (i, action) in actions.indexed)
                _ActionRow(
                  key: action.$1,
                  icon: action.$2,
                  label: action.$3,
                  onTap: action.$4,
                  divider: i < actions.length - 1,
                ),
            ],
          ),
        ),
        if (contacts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 32,
              end: 16,
              bottom: 6,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.newMessageContacts,
                style: TextStyle(
                  color: tokens.mut,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.48,
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: tokens.surf,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry in contacts)
                  _ContactRow(
                    entry: entry,
                    onTap: () => controller.openUserModal(
                      Profile(userId: entry.userId, displayName: entry.name),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool divider;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.divider,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Row(
              spacing: 14,
              children: [
                Icon(icon, size: 23, color: tokens.acc),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    alignment: AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(
                      border: divider
                          ? Border(bottom: BorderSide(color: tokens.line))
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: tokens.acc,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ContactEntry entry;
  final VoidCallback onTap;

  const _ContactRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final status =
        entry.status ??
        (entry.lastSeen == null
            ? entry.userId
            : entry.lastSeen!.localizedTimeShort(context));
    return Semantics(
      button: true,
      label: '${entry.name}, $status',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              spacing: 12,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Avatar(name: entry.name, size: 44, colorSeed: entry.userId),
                    if (entry.online)
                      PositionedDirectional(
                        end: -1,
                        bottom: -1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: tokens.ok,
                            shape: BoxShape.circle,
                            border: Border.all(color: tokens.surf, width: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: entry.online ? tokens.acc : tokens.mut,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryResults extends StatelessWidget {
  final NewPrivateChatController controller;
  final Future<List<Profile>> future;

  const _DirectoryResults({required this.controller, required this.future});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return FutureBuilder(
      future: future,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final error = snapshot.error;
        if (error != null) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 12,
            children: [
              Text(
                error.toLocalizedString(context),
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.red),
              ),
              OutlinedButton.icon(
                onPressed: controller.searchUsers,
                icon: const Icon(Icons.refresh_outlined),
                label: Text(l10n.tryAgain),
              ),
            ],
          );
        }
        if (result == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (result.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                Icon(Icons.search_off_rounded, size: 56, color: tokens.mut),
                Text(
                  l10n.noUsersFoundWithQuery(
                    safeDisplayText(controller.controller.text),
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.mut),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final contact in result)
              _DirectoryRow(contact: contact, onTap: controller.openUserModal),
          ],
        );
      },
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  final Profile contact;
  final void Function(Profile profile) onTap;

  const _DirectoryRow({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final name = safeDisplayText(
      contact.displayName ?? contact.userId.localpart ?? contact.userId,
    );
    return Semantics(
      button: true,
      label: '$name, ${contact.userId}',
      excludeSemantics: true,
      onTap: () => onTap(contact),
      child: InkWell(
        onTap: () => onTap(contact),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 12,
              children: [
                Avatar(
                  name: name,
                  mxContent: contact.avatarUrl,
                  size: 44,
                  colorSeed: contact.userId,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        contact.userId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: tokens.mut,
                          fontSize: 12.5,
                          fontFamily: AppTypography.monoFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
