// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/themes.dart';

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
    return Scaffold(
      body: Row(
        children: [
          if (rail != null) ...[_ReadingOrderColumn(rail!), divider],
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(),
            width: FluffyThemes.listColumnWidth,
            child: _ReadingOrderColumn(mainView),
          ),
          divider,
          Expanded(child: ClipRRect(child: _ReadingOrderColumn(sideView))),
        ],
      ),
    );
  }
}

/// Tab walks one column completely before it enters the next one.
class _ReadingOrderColumn extends StatelessWidget {
  final Widget child;

  const _ReadingOrderColumn(this.child);

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(), child: child);
}
