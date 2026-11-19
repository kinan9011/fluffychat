// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/pages/settings_folders/folder_actions.dart';
import 'package:odango/pages/settings_folders/folder_chat_picker.dart';
import 'package:odango/pages/settings_folders/folder_editor_view.dart';
import 'package:odango/utils/chat_list/folder_store.dart';
import 'package:odango/widgets/future_loading_dialog.dart';
import 'package:odango/widgets/matrix.dart';

class FolderEditor extends StatefulWidget {
  final String? folderId;

  const FolderEditor({this.folderId, super.key});

  @override
  FolderEditorController createState() => FolderEditorController();
}

class FolderEditorController extends State<FolderEditor> {
  late final Client client;
  late final String folderId;
  late final bool isNew;
  late final TextEditingController nameController;
  StreamSubscription<Client>? _clientSubscription;

  var types = <FolderChatType>{};
  var rooms = <String>[];
  var excludeMuted = false;
  var excludeRead = false;
  var readOnly = false;

  UserFolder? get existing => FolderStore.of(
    client,
  ).folders.where((folder) => folder.id == folderId).firstOrNull;

  bool get limitReached =>
      isNew && FolderStore.of(client).folders.length >= FolderStore.maxFolders;

  bool get canSave =>
      !readOnly &&
      !limitReached &&
      FolderStore.sanitizeName(nameController.text).isNotEmpty;

  @override
  void initState() {
    super.initState();
    final matrix = Matrix.of(context);
    client = matrix.client;
    final document = FolderStore.of(client);
    readOnly = document.readOnly;
    final requested = FolderStore.isValidId(widget.folderId)
        ? widget.folderId
        : null;
    final current = document.folders
        .where((folder) => folder.id == requested)
        .firstOrNull;
    isNew = current == null;
    folderId = current?.id ?? FolderStore.newId();
    nameController = TextEditingController(text: current?.name ?? '');
    types = {...?current?.types};
    rooms = [...?current?.rooms];
    excludeMuted = current?.excludeMuted ?? false;
    excludeRead = current?.excludeRead ?? false;
    _clientSubscription = matrix.onActiveClientChanged.listen((_) {
      if (mounted) context.go('/settings/chat/folders');
    });
  }

  @override
  void dispose() {
    _clientSubscription?.cancel();
    nameController.dispose();
    super.dispose();
  }

  void setType(FolderChatType type, bool value) => setState(
    () => types = {
      for (final other in types)
        if (other != type) other,
      if (value) type,
    },
  );

  void setExcludeMuted(bool value) => setState(() => excludeMuted = value);

  void setExcludeRead(bool value) => setState(() => excludeRead = value);

  void removeRoom(String id) => setState(() => rooms = [...rooms]..remove(id));

  void setRooms(List<String> newRooms) => setState(
    () => rooms = newRooms.take(FolderStore.maxRoomsPerFolder).toList(),
  );

  Future<void> addChats() async {
    final picked = await showFolderChatPicker(context, client, selected: rooms);
    if (picked != null) setRooms(picked);
  }

  Future<void> save() async {
    if (!canSave) return;
    final folder = UserFolder(
      id: folderId,
      name: FolderStore.sanitizeName(nameController.text),
      types: types,
      rooms: rooms,
      excludeMuted: excludeMuted,
      excludeRead: excludeRead,
    );
    final current = FolderStore.of(client).folders;
    final updated = isNew || existing == null
        ? [...current, folder]
        : [for (final other in current) other.id == folderId ? folder : other];
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => FolderStore.save(client, updated),
    );
    if (result.error != null || !mounted) return;
    context.go('/settings/chat/folders');
  }

  Future<void> delete() async {
    final folder = existing;
    if (folder == null || readOnly) return;
    if (!await deleteFolder(context, client, folder) || !mounted) return;
    context.go('/settings/chat/folders');
  }

  @override
  Widget build(BuildContext context) => FolderEditorView(this);
}
