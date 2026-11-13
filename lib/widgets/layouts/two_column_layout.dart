// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

class TwoColumnLayout extends StatelessWidget {
  final Widget? rail;
  final Widget mainView;
  final Widget sideView;

  const TwoColumnLayout({
    super.key,
    required this.mainView,
    required this.sideView,
    this.rail,
  });

  @override
  Widget build(BuildContext context) {
    final divider = Container(
      width: 1.0,
      color: Theme.of(context).dividerColor,
    );
    return ScaffoldMessenger(
      child: Scaffold(
        body: Row(
          children: [
            if (rail != null) ...[rail!, divider],
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              width: FluffyThemes.listColumnWidth,
              child: mainView,
            ),
            divider,
            Expanded(child: ClipRRect(child: sideView)),
          ],
        ),
      ),
    );
  }
}
