// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_folders/settings_folders.dart';
import 'package:fluffychat/utils/chat_list/folder_store.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:material_ui/material_ui.dart';

class SettingsFoldersView extends StatelessWidget {
  final SettingsFoldersController controller;

  const SettingsFoldersView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = controller.client;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.folders),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          key: ValueKey(client.clientName),
          stream: client.onSync.stream.where(
            (sync) => sync.accountData?.isNotEmpty ?? false,
          ),
          builder: (context, _) {
            final document = FolderStore.of(client);
            final full = document.folders.length >= FolderStore.maxFolders;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    l10n.folderSyncNotice,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (document.readOnly)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(
                      document.unreadable
                          ? l10n.foldersUnreadable
                          : l10n.foldersFromNewerVersion,
                    ),
                  ),
                for (final folder in document.folders)
                  ListTile(
                    key: ValueKey('folder_${folder.id}'),
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      l10n.countChats(
                        client.rooms
                            .where(
                              (room) =>
                                  !room.isJoinedSpace &&
                                  !room.isArchivedChat &&
                                  folder.matches(room),
                            )
                            .length,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_outlined),
                    onTap: () => controller.edit(folder.id),
                  ),
                if (!document.readOnly)
                  ListTile(
                    key: const ValueKey('create_folder'),
                    enabled: !full,
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: Text(l10n.createFolder),
                    subtitle: full
                        ? Text(l10n.folderLimitReached(FolderStore.maxFolders))
                        : null,
                    onTap: full ? null : controller.create,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
