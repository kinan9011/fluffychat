// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/pages/calls/calls_view.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  CallsController createState() => CallsController();
}

class CallsController extends State<CallsPage> {
  late Future<ServerCapabilities> capabilities;
  StreamSubscription<Client>? _activeClientSubscription;

  void _load() {
    final matrix = Matrix.of(context);
    capabilities = matrix.serverCapabilities.load(matrix.client);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _activeClientSubscription = Matrix.of(
      context,
    ).onActiveClientChanged.listen((_) => setState(_load));
  }

  @override
  void dispose() {
    _activeClientSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallsView(this);
}
