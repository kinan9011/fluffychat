// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/widgets/matrix.dart';

/// Builds with whether the call entry points of [client] are available and
/// rebuilds when that changes (server capability, setting, account switch).
class CallsGate extends StatelessWidget {
  final Client client;
  final Widget Function(BuildContext context, bool available) builder;

  const CallsGate({required this.client, required this.builder, super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    return ListenableBuilder(
      listenable: matrix.callsAvailability,
      builder: (context, _) =>
          builder(context, matrix.callsAvailableFor(client)),
    );
  }
}
