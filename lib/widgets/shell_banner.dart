// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// A banner above the app shell. [AppShell] has no Scaffold and the two-column
/// layout has its own ScaffoldMessenger, so a messenger banner is not reliable
/// there. The child keeps its key so hiding the banner never rebuilds it.
class ShellBanner extends StatefulWidget {
  final bool Function() isVisible;
  final IconData icon;
  final String message;
  final List<Widget> Function(VoidCallback hide) actions;
  final Widget child;

  const ShellBanner({
    required this.isVisible,
    required this.icon,
    required this.message,
    required this.actions,
    required this.child,
    super.key,
  });

  @override
  State<ShellBanner> createState() => _ShellBannerState();
}

class _ShellBannerState extends State<ShellBanner> {
  bool _hidden = false;

  void _hide() => setState(() => _hidden = true);

  @override
  Widget build(BuildContext context) {
    final show = !_hidden && widget.isVisible();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        if (show)
          SafeArea(
            bottom: false,
            child: MaterialBanner(
              backgroundColor: colorScheme.errorContainer,
              contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
              leading: Icon(widget.icon, color: colorScheme.onErrorContainer),
              content: Text(widget.message),
              actions: widget.actions(_hide),
            ),
          ),
        Expanded(
          key: const ValueKey('shell-banner-content'),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: show,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
