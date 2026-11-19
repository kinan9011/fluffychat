// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/chat_list/folder_store.dart';
import 'package:odango/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/widgets/avatar.dart';

Future<List<String>?> showFolderChatPicker(
  BuildContext context,
  Client client, {
  required List<String> selected,
}) => showDialog<List<String>>(
  context: context,
  builder: (context) => _FolderChatPicker(client: client, selected: selected),
);

class _FolderChatPicker extends StatefulWidget {
  final Client client;
  final List<String> selected;

  const _FolderChatPicker({required this.client, required this.selected});

  @override
  State<_FolderChatPicker> createState() => _FolderChatPickerState();
}

class _FolderChatPickerState extends State<_FolderChatPicker> {
  late final selected = [...widget.selected];
  var filter = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locals = MatrixLocals(l10n);
    final rooms = [
      for (final room in widget.client.rooms)
        if (!room.isJoinedSpace &&
            room
                .getLocalizedDisplayname(locals)
                .toLowerCase()
                .contains(filter.toLowerCase()))
          room,
    ];
    return AlertDialog(
      title: Text(l10n.addChats),
      content: SizedBox(
        width: 400,
        height: min(420, MediaQuery.sizeOf(context).height * 0.5),
        child: Column(
          children: [
            TextField(
              key: const ValueKey('folder_chat_search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l10n.search,
              ),
              onChanged: (value) => setState(() => filter = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  final name = room.getLocalizedDisplayname(locals);
                  final isSelected = selected.contains(room.id);
                  return CheckboxListTile(
                    key: ValueKey('picker_${room.id}'),
                    value: isSelected,
                    secondary: Avatar(
                      mxContent: room.avatar,
                      client: widget.client,
                      name: name,
                      colorSeed: room.avatarColorSeed,
                      size: 36,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged:
                        !isSelected &&
                            selected.length >= FolderStore.maxRoomsPerFolder
                        ? null
                        : (value) => setState(
                            () => value == true
                                ? selected.add(room.id)
                                : selected.remove(room.id),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('folder_chat_picker_done'),
          onPressed: () => Navigator.of(context).pop(selected),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
