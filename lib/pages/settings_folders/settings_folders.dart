// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/pages/settings_folders/settings_folders_view.dart';
import 'package:odango/widgets/matrix.dart';

class SettingsFolders extends StatefulWidget {
  const SettingsFolders({super.key});

  @override
  SettingsFoldersController createState() => SettingsFoldersController();
}

class SettingsFoldersController extends State<SettingsFolders> {
  StreamSubscription<Client>? _clientSubscription;

  Client get client => Matrix.of(context).client;

  void create() => context.go('/settings/chat/folders/edit');

  void edit(String id) => context.go('/settings/chat/folders/edit?id=$id');

  @override
  void initState() {
    super.initState();
    _clientSubscription = Matrix.of(
      context,
    ).onActiveClientChanged.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _clientSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsFoldersView(this);
}
