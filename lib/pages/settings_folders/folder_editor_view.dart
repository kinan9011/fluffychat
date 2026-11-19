// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/themes.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/settings_folders/folder_editor.dart';
import 'package:odango/utils/chat_list/folder_store.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/widgets/layouts/max_width_body.dart';

class FolderEditorView extends StatelessWidget {
  final FolderEditorController controller;

  const FolderEditorView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final client = controller.client;
    final readOnly = controller.readOnly;
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.isNew ? l10n.createFolder : l10n.editFolder),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        actions: [
          ListenableBuilder(
            listenable: controller.nameController,
            builder: (context, _) => TextButton(
              key: const ValueKey('save_folder'),
              onPressed: controller.canSave ? controller.save : null,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.limitReached)
              ListTile(
                key: const ValueKey('folder_limit'),
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.folderLimitReached(FolderStore.maxFolders)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('folder_name'),
                controller: controller.nameController,
                enabled: !readOnly,
                maxLength: FolderStore.maxNameLength,
                decoration: InputDecoration(labelText: l10n.folderName),
              ),
            ),
            ListTile(
              title: Text(
                l10n.folderChatTypes,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            CheckboxListTile.adaptive(
              value: controller.types.contains(FolderChatType.dm),
              title: Text(l10n.personal),
              onChanged: readOnly
                  ? null
                  : (value) =>
                        controller.setType(FolderChatType.dm, value == true),
            ),
            CheckboxListTile.adaptive(
              value: controller.types.contains(FolderChatType.group),
              title: Text(l10n.groups),
              onChanged: readOnly
                  ? null
                  : (value) =>
                        controller.setType(FolderChatType.group, value == true),
            ),
            SwitchListTile.adaptive(
              value: controller.excludeMuted,
              title: Text(l10n.excludeMutedChats),
              onChanged: readOnly ? null : controller.setExcludeMuted,
            ),
            SwitchListTile.adaptive(
              value: controller.excludeRead,
              title: Text(l10n.excludeReadChats),
              onChanged: readOnly ? null : controller.setExcludeRead,
            ),
            const Divider(),
            ListTile(
              title: Text(
                l10n.chats,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final id in controller.rooms)
              ListTile(
                key: ValueKey('folder_room_$id'),
                title: Text(
                  client
                          .getRoomById(id)
                          ?.getLocalizedDisplayname(MatrixLocals(l10n)) ??
                      AppTypography.ltr(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: l10n.remove,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: readOnly ? null : () => controller.removeRoom(id),
                ),
              ),
            if (!readOnly)
              ListTile(
                key: const ValueKey('add_chats'),
                leading: const Icon(Icons.add_rounded),
                title: Text(l10n.addChats),
                enabled:
                    controller.rooms.length < FolderStore.maxRoomsPerFolder,
                onTap: controller.addChats,
              ),
            if (!readOnly && !controller.isNew) ...[
              const Divider(),
              ListTile(
                key: const ValueKey('delete_folder'),
                leading: Icon(
                  Icons.delete_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l10n.deleteFolder,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: controller.delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
