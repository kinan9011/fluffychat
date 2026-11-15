// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_folders/folder_actions.dart';
import 'package:fluffychat/utils/chat_list/folder_store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum FolderTabAction { edit, delete }

Future<void> showUserFolderTabMenu(
  BuildContext context,
  Client client,
  String folderId,
) async {
  final folder = FolderStore.of(
    client,
  ).folders.where((folder) => folder.id == folderId).firstOrNull;
  if (folder == null || FolderStore.of(client).readOnly) return;
  final l10n = L10n.of(context);
  final action = await showModalActionPopup<FolderTabAction>(
    context: context,
    actions: [
      AdaptiveModalAction(value: FolderTabAction.edit, label: l10n.editFolder),
      AdaptiveModalAction(
        value: FolderTabAction.delete,
        label: l10n.deleteFolder,
        isDestructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case FolderTabAction.edit:
      context.go('/settings/chat/folders/edit?id=${folder.id}');
    case FolderTabAction.delete:
      await deleteFolder(context, client, folder);
  }
}
